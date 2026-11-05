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
# Et `member_paid` (Michael, 2026-10-22) : un membre l'a payée en magasin et se
# la fait rembourser par sa note de frais. C'est la ligne de la note qui porte
# la charge (`ExpenseLine#purchase_invoice`) : la facture devient son
# justificatif et ne se comptabilise jamais elle-même, sans quoi les 24 € de
# l'achat compteraient deux fois.
#
# La comptabilisation n'est PAS un statut : c'est `posted_at`. Un statut qui
# mélangerait l'état administratif et l'état comptable rendrait impossible de
# dire « payée mais pas encore passée ».
#
# **Les notes de crédit** (Michael, 2026-11-01) : `kind` = `credit_note`. Le
# montant reste positif, c'est le type qui inverse l'écriture (440000 au débit,
# charge au crédit). Liée à la facture qu'elle corrige (`credited_invoice`),
# elle s'impute sur ce qui en reste à payer ; ce qui ne s'y impute pas (facture
# déjà payée, ou pas de facture liée) attend un remboursement du fournisseur,
# rapproché d'une ligne bancaire ENTRANTE. Même parcours de statuts : « À
# payer » se lit alors « À rembourser ».
# == Schema Information
#
# Table name: purchase_invoices
#
#  id                  :bigint           not null, primary key
#  deleted_at          :datetime
#  dispute_reason      :text
#  due_on              :date
#  issued_on           :date             not null
#  kind                :string           default("invoice"), not null
#  notes               :text
#  number              :string
#  paid_on             :date
#  payment_reference   :string
#  pdf_sha256          :string
#  posted_at           :datetime
#  quality_flags       :jsonb            not null
#  requires_validation :boolean          default(FALSE), not null
#  status              :string           default("to_process"), not null
#  total_cents         :integer          default(0), not null
#  validated_at        :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  credited_invoice_id :bigint
#  legal_entity_id     :bigint           not null
#  third_party_id      :bigint           not null
#  validated_by_id     :bigint
#  validation_team_id  :bigint
#
# Indexes
#
#  index_purchase_invoices_on_credited_invoice_id     (credited_invoice_id)
#  index_purchase_invoices_on_deleted_at              (deleted_at)
#  index_purchase_invoices_on_legal_entity_id         (legal_entity_id)
#  index_purchase_invoices_on_pdf_sha256              (pdf_sha256) UNIQUE WHERE (deleted_at IS NULL)
#  index_purchase_invoices_on_status                  (status)
#  index_purchase_invoices_on_third_party_and_number  (third_party_id,kind,number) UNIQUE WHERE ((deleted_at IS NULL) AND (number IS NOT NULL))
#  index_purchase_invoices_on_third_party_id          (third_party_id)
#  index_purchase_invoices_on_validated_by_id         (validated_by_id)
#  index_purchase_invoices_on_validation_team_id      (validation_team_id)
#
# Foreign Keys
#
#  fk_rails_...  (credited_invoice_id => purchase_invoices.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (third_party_id => third_parties.id)
#  fk_rails_...  (validated_by_id => users.id)
#  fk_rails_...  (validation_team_id => teams.id)
#
class PurchaseInvoice < ApplicationRecord
  # Ordre volontaire : c'est celui du parcours, et l'écran s'en sert pour ses
  # totaux en tête de liste.
  STATUSES = %w[to_process to_validate to_pay paid member_paid disputed].freeze
  STATUS_LABELS = {
    "to_process"  => "À traiter",
    "to_validate" => "À valider",
    "to_pay"      => "À payer",
    "paid"        => "Payée",
    "member_paid" => "Payée par un membre",
    "disputed"    => "Contestée"
  }.freeze

  # Au-delà, la banque exige deux signatures (décision 7). C'est une
  # information affichée, jamais un blocage : bloquer ferait rentrer la facture
  # par un autre chemin, et on ne la verrait plus du tout.
  DOUBLE_SIGNATURE_CENTS = 500_000

  # Les statuts où le contenu est gelé : l'écriture est passée, la corriger
  # voudrait dire réécrire le grand livre.
  FROZEN_STATUSES = %w[to_pay paid].freeze

  # Les statuts d'une facture réglée : elle n'est plus jamais échue.
  SETTLED_STATUSES = %w[paid member_paid].freeze

  KINDS = %w[invoice credit_note].freeze
  KIND_LABELS = {
    "invoice"     => "Facture",
    "credit_note" => "Note de crédit"
  }.freeze

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
  # La facture qu'une note de crédit corrige, et l'inverse.
  belongs_to :credited_invoice, class_name: "PurchaseInvoice", optional: true
  has_many :credit_notes, class_name: "PurchaseInvoice", foreign_key: :credited_invoice_id,
                          inverse_of: :credited_invoice, dependent: :restrict_with_error
  has_many :purchase_invoice_lines, -> { order(:position, :id) }, dependent: :destroy
  # Les relevés de dépôt-vente que cette facture solde (epic #248, phase 3).
  # `nullify` : détacher une facture ne doit jamais effacer le relevé — c'est le
  # travail de l'artisan, pas une pièce jointe.
  has_many :consignment_reports, dependent: :nullify
  # Les échéances de paiement que cette facture solde (échéancier comptable) :
  # le précompte immobilier est « fait » quand SA facture est payée.
  has_many :compliance_deadlines, dependent: :nullify
  # Les lignes de note de frais qui remboursent cette facture au membre qui l'a
  # payée (`member_paid`). `nullify` : une facture ne disparaît pas, mais si
  # elle le faisait, la dépense du membre resterait due.
  has_many :expense_lines, dependent: :nullify
  # `cash_allocations` (le `document` polymorphique de la décision 4) vient du
  # concern `Payable` : c'est ce lien qui fait passer la facture en `paid`.
  has_one_attached :document

  accepts_nested_attributes_for :purchase_invoice_lines, allow_destroy: true

  # Comment le formulaire tape la ventilation : HTVA (défaut, comme une facture
  # classique) ou TVA comprise, pour toute la facture (ticket de caisse en TTC).
  # Pas stocké : ça ne change que la saisie, la ligne garde HTVA, TVA et TVAC.
  attribute :amounts_include_vat, :boolean, default: false

  before_validation :flag_quality
  before_validation :compute_vat
  before_validation :normalize_payment_reference
  validate :structured_payment_reference_is_valid
  validate :lines_cover_total_when_leaving_to_process
  validate :frozen_once_payable, on: :update
  validate :credited_invoice_is_coherent

  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :number, uniqueness: { scope: %i[third_party_id kind], allow_nil: true,
                                   message: "existe déjà pour ce tiers" }
  validates :pdf_sha256, uniqueness: { allow_nil: true,
                                       message: "correspond à une pièce déjà déposée" }
  validates :dispute_reason, presence: { message: "est obligatoire pour contester une facture" },
                             if: :disputed?

  scope :ordered, -> { order(issued_on: :desc, id: :desc) }
  # L'échéance la plus proche (ou la plus dépassée) d'abord ; sans échéance, en
  # fin de liste : elles n'ont pas de promesse à tenir.
  scope :by_due_date, -> { order(Arel.sql("purchase_invoices.due_on ASC NULLS LAST"), issued_on: :desc, id: :desc) }
  scope :with_status, ->(status) { where(status: status) }
  scope :invoices, -> { where(kind: "invoice") }
  scope :credit_notes, -> { where(kind: "credit_note") }
  # Ce qu'on doit virer : des FACTURES. Une note de crédit « À rembourser »
  # attend de l'argent qui rentre (`awaiting_refund`).
  scope :payable, -> { invoices.where(status: "to_pay") }
  scope :awaiting_refund, -> { credit_notes.where(status: "to_pay") }
  # Ce que le pôle doit trancher (phase 3) : le callout de sa page s'en sert.
  scope :awaiting_validation_by, ->(team) { where(status: "to_validate", validation_team_id: team) }

  STATUSES.each do |state|
    define_method("#{state}?") { status == state }
  end

  def credit_note? = kind == "credit_note"
  def kind_label = KIND_LABELS.fetch(kind, kind)

  # Pour une note de crédit, « À payer » et « Payée » ne disent rien : elle
  # attend un remboursement, ou elle est imputée sur sa facture / remboursée.
  def status_label
    return STATUS_LABELS.fetch(status, status) unless credit_note?
    return "À rembourser" if to_pay?
    return(allocated_cents.positive? ? "Remboursée" : "Imputée") if paid?

    STATUS_LABELS.fetch(status, status)
  end
  def lines_total_cents = purchase_invoice_lines.sum(&:amount_cents)
  def lines_vat_cents = purchase_invoice_lines.sum(&:vat_cents)
  def balanced? = lines_total_cents == total_cents
  def posted? = posted_at.present?
  def frozen_content? = FROZEN_STATUSES.include?(status)
  # Ce qui ne se modifie plus depuis le formulaire : une facture comptabilisée,
  # ou payée par un membre (sa note de frais a repris montant, compte et pôle).
  def locked_for_edit? = frozen_content? || member_paid?
  def double_signature? = !credit_note? && total_cents >= DOUBLE_SIGNATURE_CENTS
  def reference = [third_party&.name, number].compact_blank.join(" · ")
  # Le montant vu du grand livre : une note de crédit réduit les charges.
  def signed_total_cents = credit_note? ? -total_cents : total_cents

  # --- Les notes de crédit ---------------------------------------------------

  # Ce que les notes de crédit COMPTABILISÉES retirent de cette facture. Une
  # note encore à traiter n'est qu'une promesse : elle ne réduit rien.
  def credited_cents
    return 0 if credit_note?

    credit_notes.where(status: FROZEN_STATUSES).sum(:total_cents)
  end

  # Ce qu'une note de crédit comptabilisée retire de la facture qu'elle
  # corrige : au plus ce qui restait à y payer (ce que la banque n'a pas
  # encore couvert, et que des notes antérieures n'ont pas déjà pris). Le
  # surplus, le fournisseur nous le rembourse.
  def imputed_cents
    return 0 unless credit_note? && credited_invoice && FROZEN_STATUSES.include?(status)

    anterieures = credited_invoice.credit_notes.where(status: FROZEN_STATUSES).where(id: ...id).sum(:total_cents)
    (credited_invoice.total_cents - credited_invoice.allocated_cents - anterieures).clamp(0, total_cents)
  end

  # Échue = l'échéance est passée et la facture n'est pas réglée. Lu sur le
  # statut, pas sur les affectations (`payable_overdue?`) : la liste en affiche
  # des dizaines, une requête par ligne pour la même réponse serait du gâchis.
  def overdue?(on = Date.current) = !credit_note? && due_on.present? && due_on < on && !SETTLED_STATUSES.include?(status)
  def days_overdue(on = Date.current) = overdue?(on) ? (on - due_on).to_i : 0

  # Les notes de frais qui remboursent cette facture, rejetées et supprimées
  # exclues : une note rejetée ne rembourse personne.
  def settling_expense_reports
    ExpenseReport.where(id: expense_lines.select(:expense_report_id)).where.not(status: "rejected")
  end

  # --- Le contrat `Payable` ------------------------------------------------
  # La communication d'un virement fournisseur : celle qu'il demande sur sa
  # facture (souvent structurée, +++…+++, qu'il rapproche automatiquement),
  # sinon le numéro de SA facture, c'est ce qu'il cherche pour rapprocher de son
  # côté. À défaut, notre propre référence, qui vaut mieux qu'un virement muet.
  #
  # Une facture doit son total moins ses notes de crédit ; une note de crédit
  # « doit » ce que le fournisseur doit encore NOUS rembourser.
  def payable_amount_cents
    return total_cents - imputed_cents if credit_note?

    [total_cents - credited_cents, 0].max
  end

  def payable_beneficiary = third_party&.name
  def payable_third_party = third_party
  def payable_communication = payment_reference.presence || number.presence || "Facture ##{id}"
  def payable_due_on = due_on
  def payable_reference = reference.presence || "##{id}"
  def payable_label = "#{kind_label} #{payable_reference}"

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

  # « TVA manquante » parle du TIERS, pas de la pièce : on le relit à chaque
  # lecture, sinon le drapeau posé à l'encodage restait affiché après qu'on a
  # complété le numéro de TVA du fournisseur (Trois Petits Poids, 2026-11-05).
  # Les autres drapeaux (numéro, pièce jointe) sont ceux de la facture et se
  # recalculent à chaque enregistrement.
  def quality_flags
    flags = Array(super) - ["no_vat_number"]
    flags.unshift("no_vat_number") if missing_third_party_vat_number?
    flags
  end

  private

  def missing_third_party_vat_number?
    third_party.present? && third_party.vat_number.blank?
  end

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
    flags << "no_vat_number" if missing_third_party_vat_number?
    flags << "no_number" if number.blank?
    flags << "no_document" unless document.attached?
    self.quality_flags = flags
  end

  def lines_cover_total_when_leaving_to_process
    return if to_process? || disputed? || member_paid?
    return if purchase_invoice_lines.reject(&:marked_for_destruction?).sum { |l| l.amount_cents.to_i } == total_cents

    errors.add(:base, "Les lignes doivent couvrir exactement le total avant de quitter « À traiter ».")
  end

  # La TVA des lignes tapées HTVA, taux par taux, comme sur la pièce : « TVA 21 %
  # sur 1 189,11 » s'arrondit une fois sur la base du taux, pas ligne par ligne.
  # L'arrondi se répartit ensuite sur les lignes, l'écart d'un cent allant à la
  # plus grosse, pour que la somme des lignes retombe sur le TVAC de la facture.
  #
  # Une ligne tapée TVA comprise garde son montant tel quel (c'est celui de la
  # pièce) : on en extrait la TVA, 127,78 € à 6 % = 7,23 € de TVA sur 120,55 €
  # HTVA, avec le même arrondi taux par taux.
  def compute_vat
    lines = purchase_invoice_lines.reject(&:marked_for_destruction?)

    lines.select(&:net_cents).group_by { |line| line.vat_rate.to_i }.each do |rate, typed|
      spread_vat(typed, :net_cents) { |cents| (cents * rate).quo(100).round }
      typed.each { |line| line.amount_cents = line.net_cents + line.vat_cents }
    end

    lines.select { |line| line.gross_cents && !line.net_cents }.group_by { |line| line.vat_rate.to_i }.each do |rate, typed|
      spread_vat(typed, :gross_cents) { |cents| (cents * rate).quo(100 + rate).round }
      typed.each { |line| line.amount_cents = line.gross_cents }
    end
  end

  def spread_vat(lines, base)
    expected = yield(lines.sum(&base))
    lines.each { |line| line.vat_cents = yield(line.public_send(base)) }
    lines.max_by { |line| line.public_send(base).abs }.vat_cents += expected - lines.sum(&:vat_cents)
  end

  # Une facture dont l'écriture est passée ne se retouche pas : on contre-passe.
  # Une communication structurée se range sous sa forme canonique
  # (+++123/4567/89002+++), quelle que soit la façon dont on l'a tapée ou lue.
  def normalize_payment_reference
    self.payment_reference = payment_reference.to_s.strip.presence
    canonique = payment_reference && MailIntake::StructuredCommunication.normalize(payment_reference)
    self.payment_reference = canonique if canonique
  end

  # Douze chiffres dont la clé modulo 97 est fausse : c'est une faute de frappe,
  # et un virement qui la porte ne serait pas rapproché par le fournisseur.
  def structured_payment_reference_is_valid
    return if payment_reference.blank? || !payment_reference.match?(%r{\A[\s\d+*/]+\z})
    return if payment_reference.gsub(/\D/, "").length != 12 || MailIntake::StructuredCommunication.normalize(payment_reference)

    errors.add(:payment_reference, "a une clé de contrôle fausse : vérifiez les deux derniers chiffres")
  end

  def credited_invoice_is_coherent
    return if credited_invoice_id.blank?

    unless credit_note?
      errors.add(:credited_invoice, "ne se donne qu'à une note de crédit")
      return
    end
    return errors.add(:credited_invoice, "est introuvable") if credited_invoice.nil?

    errors.add(:credited_invoice, "doit être une facture, pas une note de crédit") if credited_invoice.credit_note?
    errors.add(:credited_invoice, "n'est pas du même fournisseur") if credited_invoice.third_party_id != third_party_id
    errors.add(:credited_invoice, "n'est pas de la même entité") if credited_invoice.legal_entity_id != legal_entity_id
  end

  def frozen_once_payable
    return unless FROZEN_STATUSES.include?(status_was)

    gelees = %w[total_cents third_party_id legal_entity_id issued_on number kind credited_invoice_id]
    return if (changed & gelees).empty?

    errors.add(:base, "Cette facture est déjà comptabilisée — corrige-la par contre-passation.")
  end
end
