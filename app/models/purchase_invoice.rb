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

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  belongs_to :third_party
  belongs_to :validation_team, class_name: "Team", optional: true
  belongs_to :validated_by, class_name: "User", optional: true
  has_many :purchase_invoice_lines, -> { order(:position, :id) }, dependent: :destroy
  # L'allocation de trésorerie qui la paie pointe la facture par son `document`
  # polymorphique (décision 4) : c'est ce lien qui fait passer la facture en
  # `paid` — le paiement est un rapprochement, pas une case à cocher.
  has_many :cash_allocations, as: :document, dependent: :nullify
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

  STATUSES.each do |state|
    define_method("#{state}?") { status == state }
  end

  def status_label = STATUS_LABELS.fetch(status, status)
  def allocated_cents = cash_allocations.sum(:amount_cents).abs
  def remaining_cents = total_cents - allocated_cents
  def lines_total_cents = purchase_invoice_lines.sum(&:amount_cents)
  def balanced? = lines_total_cents == total_cents
  def posted? = posted_at.present?
  def frozen_content? = FROZEN_STATUSES.include?(status)
  def double_signature? = total_cents >= DOUBLE_SIGNATURE_CENTS
  def reference = [third_party&.name, number].compact_blank.join(" · ")

  # L'étape suivante du parcours, telle que la facture la voit elle-même.
  def next_status
    return "to_validate" if requires_validation? && validated_at.blank?

    "to_pay"
  end

  private

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
