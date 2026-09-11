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
class ConsignmentReport < ApplicationRecord
  STATUSES = %w[requested declared verified settled].freeze
  STATUS_LABELS = {
    "requested" => "Demandé",
    "declared"  => "Déclaré",
    "verified"  => "Vérifié",
    "settled"   => "Réglé"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :consignor
  belongs_to :verified_by, class_name: "User", optional: true
  has_many :consignment_report_lines, -> { order(:position, :id) }, dependent: :destroy
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

  def displayed_gross_cents = verified? || settled? ? gross_cents : live_gross_cents
  def displayed_commission_cents = verified? || settled? ? commission_cents : live_commission_cents
  def displayed_net_cents = verified? || settled? ? net_cents : live_net_cents

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
