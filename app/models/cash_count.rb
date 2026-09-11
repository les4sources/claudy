# Un comptage de la caisse (epic #243, phase 3).
#
# Vingt secondes une fois par semaine, au lieu d'un écart de −628 € qu'on
# découvre en fin d'année sans pouvoir remonter à son origine. La grille des
# dénominations est gardée telle qu'elle a été tapée : un mois plus tard, c'est
# la seule façon de refaire le calcul à la main.
#
# **L'ÉCART SE FIGE** (décision 3). `expected_cents` et `difference_cents` sont
# écrits au moment de la validation et ne bougent plus jamais, même si une ligne
# de caisse arrive après coup pour le mois compté. Un écart recalculé à
# l'affichage se dissout tout seul — et c'est précisément le mécanisme qui a
# permis aux écarts de s'accumuler sans que personne ne les voie.
#
# Deux issues à un écart, jamais une troisième : on retrouve l'origine (le
# comptage reste brouillon, on va saisir la ligne manquante) ou on l'assume
# (« écart inexpliqué » : écriture d'ajustement, commentaire obligatoire).
class CashCount < ApplicationRecord
  # Billets puis pièces, du plus grand au plus petit — l'ordre dans lequel on
  # vide un tiroir-caisse.
  DENOMINATIONS = [
    50_000, 20_000, 10_000, 5_000, 2_000, 1_000, 500,
    200, 100, 50, 20, 10, 5, 2, 1
  ].freeze
  NOTES = DENOMINATIONS.select { |cents| cents >= 500 }.freeze
  COINS = (DENOMINATIONS - NOTES).freeze

  STATUSES = %w[draft validated].freeze
  RESOLUTIONS = %w[investigate unexplained].freeze
  RESOLUTION_LABELS = {
    "investigate" => "Origine à retrouver",
    "unexplained" => "Écart inexpliqué, ajusté"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :cash_account
  belongs_to :adjustment_cash_entry, class_name: "CashEntry", optional: true
  belongs_to :counted_by, class_name: "User", optional: true

  validates :counted_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :resolution, inclusion: { in: RESOLUTIONS }, allow_nil: true
  validate :comment_required_on_difference
  validate :validated_count_is_immutable, on: :update

  scope :ordered, -> { order(counted_on: :desc, id: :desc) }
  scope :validated, -> { where(status: "validated") }
  scope :drafts, -> { where(status: "draft") }

  def draft? = status == "draft"
  def validated? = status == "validated"
  def balanced? = difference_cents.zero?
  def surplus? = difference_cents.positive?
  def resolution_label = resolution.present? ? RESOLUTION_LABELS.fetch(resolution, resolution) : nil

  # Le total de la grille, en cents. Source de vérité côté serveur : le total
  # calculé en direct par le navigateur n'est qu'un confort de saisie.
  def self.total_cents(denominations)
    (denominations || {}).sum do |unit, quantity|
      unit_cents = (unit.to_s.to_f * 100).round
      next 0 unless DENOMINATIONS.include?(unit_cents)

      unit_cents * quantity.to_i
    end
  end

  def quantity_for(unit_cents)
    (denominations || {}).fetch(self.class.denomination_key(unit_cents), 0).to_i
  end

  # La clé jsonb d'une dénomination : « 50.0 », « 0.5 ». On l'écrit en euros
  # parce que c'est ce qu'on lit sur le billet.
  def self.denomination_key(unit_cents) = format("%.2f", unit_cents / 100.0)

  private

  # Un écart sans mot d'explication, c'est un écart lissé — que l'on parte le
  # chercher ou qu'on l'assume.
  def comment_required_on_difference
    return if difference_cents.to_i.zero?
    return if comment.present?

    errors.add(:comment, "est obligatoire quand la caisse ne tombe pas juste")
  end

  # Un comptage validé est un fait daté : il ne se rejoue pas.
  def validated_count_is_immutable
    return unless status_was == "validated"

    figes = %w[counted_on denominations counted_cents expected_cents difference_cents
               comment resolution status cash_account_id adjustment_cash_entry_id]
    touchees = changed & figes
    return if touchees.empty?

    errors.add(:base, "Un comptage validé ne se modifie plus — refais-en un.")
  end
end
