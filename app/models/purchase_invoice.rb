# Une facture d'achat (epic #240, phase 2).
#
# Avant, une facture fournisseur vivait dans une boîte mail : la validation était
# un blocage implicite, donc invisible — on découvrait au moment de payer que
# personne n'avait dit oui. Ici, chaque facture porte sa pièce, son statut, ses
# lignes comptables et son entité.
#
# **Le statut est la colonne vertébrale** (décision 1) : `to_process` (la pièce
# est là, les lignes ne couvrent pas encore le total) → `to_validate` quand un
# pôle doit dire oui → `to_pay` (l'écriture est générée à ce moment-là) → `paid`
# quand le rapprochement bancaire l'a couverte. Plus `disputed`, qui bloque le
# paiement tant que rien n'est corrigé.
#
# La comptabilisation n'est PAS un statut : c'est `posted_at`. Un statut qui
# mélangerait l'état administratif et l'état comptable rendrait impossible de
# dire « payée mais pas encore passée ».
# == Schema Information
#
# Table name: purchase_invoices
#
#  id                  :bigint           not null, primary key
#  deleted_at          :datetime
#  dispute_reason      :text
#  due_on              :date
#  issued_on           :date             not null
#  notes               :text
#  number              :string
#  paid_on             :date
#  pdf_sha256          :string
#  posted_at           :datetime
#  quality_flags       :jsonb            not null
#  requires_validation :boolean          default(FALSE), not null
#  status              :string           default("to_process"), not null
#  total_cents         :integer          default(0), not null
#  validated_at        :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  legal_entity_id     :bigint           not null
#  third_party_id      :bigint           not null
#  validated_by_id     :bigint
#  validation_team_id  :bigint
#
# Indexes
#
#  index_purchase_invoices_on_deleted_at              (deleted_at)
#  index_purchase_invoices_on_legal_entity_id         (legal_entity_id)
#  index_purchase_invoices_on_pdf_sha256              (pdf_sha256) UNIQUE WHERE (deleted_at IS NULL)
#  index_purchase_invoices_on_status                  (status)
#  index_purchase_invoices_on_third_party_and_number  (third_party_id,number) UNIQUE WHERE ((deleted_at IS NULL) AND (number IS NOT NULL))
#  index_purchase_invoices_on_third_party_id          (third_party_id)
#  index_purchase_invoices_on_validated_by_id         (validated_by_id)
#  index_purchase_invoices_on_validation_team_id      (validation_team_id)
#
# Foreign Keys
#
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (third_party_id => third_parties.id)
#  fk_rails_...  (validated_by_id => users.id)
#  fk_rails_...  (validation_team_id => teams.id)
#
class PurchaseInvoice < ApplicationRecord
  # Ordre volontaire : c'est celui du parcours, et l'écran s'en sert pour ses
  # totaux en tête de liste.
  STATUSES = %w[to_process to_validate to_pay paid disputed].freeze
  STATUS_LABELS = {
    "to_process"  => "À traiter",
    "to_validate" => "À valider",
    "to_pay"      => "À payer",
    "paid"        => "Payée",
    "disputed"    => "Contestée"
  }.freeze

  # Au-delà, la banque exige deux signatures (décision 7). C'est une
  # information affichée, jamais un blocage : bloquer ferait rentrer la facture
  # par un autre chemin, et on ne la verrait plus du tout.
  DOUBLE_SIGNATURE_CENTS = 500_000

  # Les statuts où le contenu est gelé : l'écriture est passée, la corriger
  # voudrait dire réécrire le grand livre.
  FROZEN_STATUSES = %w[to_pay paid].freeze

  include Commentable
  # Ce que la maison doit (epic #240, phase 4) : `cash_allocations`, le calcul de
  # ce qui reste dû et la notion de retard viennent de là — pour que la file
  # « À payer » n'ait pas à connaître les factures d'achat en particulier.
  include Payable

  # Jeton du lien de validation posé dans l'email aux membres du pôle (phase 3),
  # même patron que `MealOrder` : portée unique et expiration, donc impossible à
  # forger comme à rejouer sur une autre ressource.
  TOKEN_PURPOSE = :validate_purchase_invoice
  TOKEN_TTL = 30.days

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  belongs_to :third_party
  belongs_to :validation_team, class_name: "Team", optional: true
  belongs_to :validated_by, class_name: "User", optional: true
  has_many :purchase_invoice_lines, -> { order(:position, :id) }, dependent: :destroy
  # Les relevés de dépôt-vente que cette facture solde (epic #248, phase 3).
  # `nullify` : détacher une facture ne doit jamais effacer le relevé — c'est le
  # travail de l'artisan, pas une pièce jointe.
  has_many :consignment_reports, dependent: :nullify
  # `cash_allocations` (le `document` polymorphique de la décision 4) vient du
  # concern `Payable` : c'est ce lien qui fait passer la facture en `paid`.
  has_one_attached :document

  accepts_nested_attributes_for :purchase_invoice_lines, allow_destroy: true

  before_validation :flag_quality
  validate :lines_cover_total_when_leaving_to_process
  validate :frozen_once_payable, on: :update

  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :number, uniqueness: { scope: :third_party_id, allow_nil: true,
                                   message: "existe déjà pour ce tiers" }
  validates :pdf_sha256, uniqueness: { allow_nil: true,
                                       message: "correspond à une pièce déjà déposée" }
  validates :dispute_reason, presence: { message: "est obligatoire pour contester une facture" },
                             if: :disputed?

  scope :ordered, -> { order(issued_on: :desc, id: :desc) }
  scope :with_status, ->(status) { where(status: status) }
  scope :payable, -> { where(status: "to_pay") }
  # Ce que le pôle doit trancher (phase 3) : le callout de sa page s'en sert.
  scope :awaiting_validation_by, ->(team) { where(status: "to_validate", validation_team_id: team) }

  STATUSES.each do |state|
    define_method("#{state}?") { status == state }
  end

  def status_label = STATUS_LABELS.fetch(status, status)
  def lines_total_cents = purchase_invoice_lines.sum(&:amount_cents)
  def balanced? = lines_total_cents == total_cents
  def posted? = posted_at.present?
  def frozen_content? = FROZEN_STATUSES.include?(status)
  def double_signature? = total_cents >= DOUBLE_SIGNATURE_CENTS
  def reference = [third_party&.name, number].compact_blank.join(" · ")

  # --- Le contrat `Payable` ------------------------------------------------
  # La communication d'un virement fournisseur, c'est le numéro de SA facture :
  # c'est ce qu'il cherche pour rapprocher de son côté. À défaut, notre propre
  # référence, qui vaut mieux qu'un virement muet.
  def payable_amount_cents = total_cents
  def payable_beneficiary = third_party&.name
  def payable_third_party = third_party
  def payable_communication = number.presence || "Facture ##{id}"
  def payable_due_on = due_on
  def payable_reference = reference.presence || "##{id}"
  def payable_label = "Facture #{payable_reference}"

  def payable_path
    Rails.application.routes.url_helpers.finance_purchase_invoice_path(self)
  end

  # Les membres du pôle qui ont un COMPTE : ceux qu'on peut notifier dans Claudy
  # (epic #242, phase 3). Distinct de ceux qu'on peut seulement emailer.
  def validation_users
    return User.none if validation_team_id.blank?

    User.where(human_id: TeamMembership.where(team_id: validation_team_id).select(:human_id))
  end

  # Qui est prévenu d'un commentaire : le pôle qui doit trancher, et la
  # coordination comptable. Une question posée dans le vide ne sert à rien.
  def comment_recipients
    (validation_users.to_a + NotificationSettingsController.accounting_users.to_a).compact.uniq
  end

  def comment_label = "la facture #{reference.presence || "##{id}"}"

  def comment_path
    Rails.application.routes.url_helpers.finance_purchase_invoice_path(self)
  end

  # L'étape suivante du parcours, telle que la facture la voit elle-même.
  def next_status
    return "to_validate" if requires_validation? && validated_at.blank?

    "to_pay"
  end

  # Le pôle apprend dans Claudy qu'une facture l'attend (epic #242, phase 3).
  # Posé sur le MODÈLE : la facture peut basculer en `to_validate` depuis le
  # bouton « Envoyer au paiement », et demain depuis un import — une notification
  # accrochée à un seul chemin manquerait l'autre.
  after_update_commit :notify_validation_team, if: :saved_change_to_awaiting_validation?

  def validation_token
    signed_id(purpose: TOKEN_PURPOSE, expires_in: TOKEN_TTL)
  end

  # Résout un jeton. nil si invalide, expiré, ou émis pour une autre portée —
  # jamais d'exception, jamais une autre ressource.
  def self.find_by_validation_token(token)
    find_signed(token, purpose: TOKEN_PURPOSE)
  end

  # Qui peut trancher : les membres du pôle désigné, et les comptes sans membre
  # rattaché (accueil générique, comptabilité — cf. `User#global_admin?`), qui
  # doivent pouvoir débloquer une facture quand le pôle ne répond pas.
  def validatable_by?(user)
    return false if user.blank?
    return true if user.global_admin?
    return false if validation_team.blank?

    validation_team.team_memberships.where(human_id: user.human_id).exists?
  end

  # Les membres du pôle qui ont une adresse : les destinataires du lien.
  def validation_recipients
    return [] if validation_team.blank?

    validation_team.humans.where.not(email: [nil, ""]).distinct
  end

  private

  def saved_change_to_awaiting_validation?
    before, after = saved_change_to_status
    after == "to_validate" && before != "to_validate"
  end

  def notify_validation_team
    Notifications::PurchaseInvoiceToValidate.call(self)
  end

  # Un défaut de métadonnée ne bloque jamais l'entrée d'une pièce (décision 7) :
  # on la marque, et quelqu'un corrige le tiers quand il a le temps.
  def flag_quality
    flags = []
    flags << "no_vat_number" if third_party.present? && third_party.vat_number.blank?
    flags << "no_number" if number.blank?
    flags << "no_document" unless document.attached?
    self.quality_flags = flags
  end

  def lines_cover_total_when_leaving_to_process
    return if to_process? || disputed?
    return if purchase_invoice_lines.reject(&:marked_for_destruction?).sum { |l| l.amount_cents.to_i } == total_cents

    errors.add(:base, "Les lignes doivent couvrir exactement le total avant de quitter « À traiter ».")
  end

  # Une facture dont l'écriture est passée ne se retouche pas : on contre-passe.
  def frozen_once_payable
    return unless FROZEN_STATUSES.include?(status_was)

    gelees = %w[total_cents third_party_id legal_entity_id issued_on number]
    return if (changed & gelees).empty?

    errors.add(:base, "Cette facture est déjà comptabilisée — corrige-la par contre-passation.")
  end
end
