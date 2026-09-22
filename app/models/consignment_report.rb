# Le relevé mensuel d'un artisan en dépôt-vente (epic #248, décision 2).
#
# L'artisan connaît son stock ; c'est lui qui déclare ce qu'il a vendu, depuis
# son téléphone, par un lien à jeton — sans compte dans Claudy. L'administration
# vérifie ensuite, et règle. Avant, Eline tenait un Excel que personne d'autre
# ne voyait.
#
# Quatre états, dans l'ordre : `requested` (le lien est parti), `declared`
# (l'artisan a envoyé ses ventes ; il peut encore les corriger), `verified`
# (l'administration a figé les totaux, phase 3), `settled` (payé, phase 3).
# == Schema Information
#
# Table name: consignment_reports
#
#  id                  :bigint           not null, primary key
#  commission_cents    :integer          default(0), not null
#  commission_percent  :integer
#  declared_at         :datetime
#  deleted_at          :datetime
#  gross_cents         :integer          default(0), not null
#  net_cents           :integer          default(0), not null
#  notes               :text
#  period_month        :date             not null
#  posted_at           :datetime
#  requested_at        :datetime
#  settled_on          :date
#  status              :string           default("requested"), not null
#  token               :string           not null
#  verified_at         :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  consignor_id        :bigint           not null
#  legal_entity_id     :bigint
#  purchase_invoice_id :bigint
#  verified_by_id      :bigint
#
# Indexes
#
#  index_consignment_reports_on_consignor_and_month  (consignor_id,period_month) UNIQUE WHERE (deleted_at IS NULL)
#  index_consignment_reports_on_consignor_id         (consignor_id)
#  index_consignment_reports_on_deleted_at           (deleted_at)
#  index_consignment_reports_on_legal_entity_id      (legal_entity_id)
#  index_consignment_reports_on_purchase_invoice_id  (purchase_invoice_id)
#  index_consignment_reports_on_token                (token) UNIQUE
#  index_consignment_reports_on_verified_by_id       (verified_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (consignor_id => consignors.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (purchase_invoice_id => purchase_invoices.id)
#  fk_rails_...  (verified_by_id => users.id)
#
class ConsignmentReport < ApplicationRecord
  STATUSES = %w[requested declared verified settled].freeze
  STATUS_LABELS = {
    "requested" => "Demandé",
    "declared"  => "Déclaré",
    "verified"  => "Vérifié",
    "settled"   => "Réglé"
  }.freeze

  # Ce que la maison doit à l'artisan (epic #240, phase 4). En mode `transfer`
  # seulement : en mode `invoice`, c'est la facture d'achat qui porte la dette,
  # et c'est elle qui apparaît dans la file « À payer ».
  include Payable

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :consignor
  belongs_to :verified_by, class_name: "User", optional: true
  belongs_to :legal_entity, optional: true
  # Mode `invoice` : la facture que l'artisan a envoyée. C'est son paiement qui
  # solde le relevé — on ne coche jamais « réglé » à côté.
  belongs_to :purchase_invoice, optional: true
  has_many :journal_entries, as: :source, dependent: :restrict_with_error
  # `inverse_of` explicite : le scope empêche Rails de le deviner, et un relevé
  # créé avec ses lignes (espace artisan, epic #359) doit être vu par elles.
  has_many :consignment_report_lines, -> { order(:position, :id) }, dependent: :destroy,
                                      inverse_of: :consignment_report
  # Stock de début et de fin de mois : l'artisan photographie son armoire. C'est
  # facultatif, et c'est ce qui permet de lever un doute sans se déplacer.
  has_many_attached :photos

  accepts_nested_attributes_for :consignment_report_lines, allow_destroy: true

  before_validation :normalize_period
  before_validation :generate_token, on: :create

  validates :period_month, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :token, presence: true, uniqueness: true
  validates :consignor_id, uniqueness: { scope: :period_month,
                                         message: "a déjà un relevé pour ce mois" }

  scope :ordered, -> { order(period_month: :desc, id: :desc) }
  scope :for_month, ->(month) { where(period_month: month.beginning_of_month) }
  scope :pending_declaration, -> { where(status: "requested") }
  # Vérifiés mais pas encore réglés : ce que la file « À payer » et le
  # rapprochement bancaire ont à traiter.
  scope :awaiting_settlement, -> { where(status: "verified") }

  STATUSES.each do |state|
    define_method("#{state}?") { status == state }
  end

  def status_label = STATUS_LABELS.fetch(status, status)

  # Modifiable par l'artisan tant que l'administration n'a rien figé. Une fois
  # vérifié, le relevé est ce sur quoi on paie : il ne bouge plus tout seul.
  def editable_by_consignor? = requested? || declared?

  def period_label = I18n.l(period_month, format: "%B %Y")
  def reference = "DV-#{period_month.strftime('%Y%m')}-#{id}"

  # Les totaux VIVANTS, recalculés depuis les lignes. Ils servent tant que le
  # relevé n'est pas vérifié ; à la vérification (phase 3) ils sont copiés dans
  # les colonnes, qui ne bougent plus.
  def live_gross_cents = consignment_report_lines.sum(&:amount_cents)

  def live_commission_cents
    (live_gross_cents * consignor.commission_percent / 100.0).round
  end

  def live_net_cents = live_gross_cents - live_commission_cents

  def displayed_gross_cents = frozen_totals? ? gross_cents : live_gross_cents
  def displayed_commission_cents = frozen_totals? ? commission_cents : live_commission_cents
  def displayed_net_cents = frozen_totals? ? net_cents : live_net_cents

  # Les totaux sont figés dès la vérification : c'est sur eux qu'on paie.
  def frozen_totals? = verified? || settled?

  # Le taux appliqué : celui figé à la vérification, sinon celui du contrat
  # aujourd'hui. Un contrat renégocié ne réécrit pas un relevé déjà vérifié.
  def applied_commission_percent
    commission_percent.presence || consignor&.commission_percent
  end

  # Modifiable par l'administration tant que rien n'est figé ni comptabilisé.
  def editable_by_admin? = requested? || declared?

  def posted? = journal_entries.any?
  def journal_entry = journal_entries.find { |entry| entry.journal == "purchases" }

  # --- Contrat `Payable` (epic #248, phase 3) ---------------------------------
  #
  # Ce qu'on doit, c'est le NET : la commission reste à la maison. L'IBAN vient
  # de l'artisan (chiffré sur `consignors`), jamais d'un tiers comptable — c'est
  # le compte que l'artisan a donné en signant son contrat.

  def payable_amount_cents = net_cents.to_i
  def payable_beneficiary = consignor&.name.to_s
  def payable_iban = consignor&.iban
  def payable_third_party = consignor&.third_party
  def payable_communication = reference
  def payable_reference = reference
  def payable_label = "Dépôt-vente #{period_label} — #{consignor&.name}"

  def payable_path
    Rails.application.routes.url_helpers.finance_consignment_report_path(self)
  end

  # Seul un relevé en mode VIREMENT, vérifié et comptabilisé, attend un virement.
  # En mode facture, la dette est portée par la facture d'achat : la faire aussi
  # apparaître ici la compterait deux fois dans le total à payer.
  def awaiting_transfer?
    consignor&.transfer? && verified? && posted?
  end

  private

  def normalize_period
    self.period_month = period_month.beginning_of_month if period_month.present?
  end

  # Jeton long et non devinable : c'est la seule chose qui protège la page de
  # déclaration, qui n'a ni session ni mot de passe.
  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end
end
