# Une ligne d'une note de frais (epic #241).
#
# Une ligne, c'est une dépense : une date, un fournisseur, un libellé, un
# montant, le compte de charge et le pôle qui la porte. Le ticket ou la facture
# se dépose ici — en photo depuis un téléphone, ou en PDF.
#
# Les colonnes kilométriques (`distance_km`, `rate_cents_per_km`) existent dès
# maintenant, mais c'est la phase 2 qui les remplit : le taux est FIGÉ sur la
# ligne au moment de la saisie, pour qu'un changement de barème ne réécrive
# jamais une note passée.
# == Schema Information
#
# Table name: expense_lines
#
#  id                  :bigint           not null, primary key
#  amount_cents        :bigint           default(0), not null
#  deleted_at          :datetime
#  distance_km         :decimal(8, 1)
#  doc_kind            :string
#  label               :string           not null
#  position            :integer          default(0), not null
#  rate_cents_per_km   :integer
#  spent_on            :date             not null
#  supplier_name       :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  analytic_account_id :bigint
#  expense_report_id   :bigint           not null
#  general_account_id  :bigint
#  team_id             :bigint
#
# Indexes
#
#  index_expense_lines_on_analytic_account_id  (analytic_account_id)
#  index_expense_lines_on_deleted_at           (deleted_at)
#  index_expense_lines_on_expense_report_id    (expense_report_id)
#  index_expense_lines_on_general_account_id   (general_account_id)
#  index_expense_lines_on_team_id              (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (expense_report_id => expense_reports.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (team_id => teams.id)
#
class ExpenseLine < ApplicationRecord
  DOC_KINDS = %w[ticket invoice].freeze
  DOC_KIND_LABELS = {
    "ticket" => "Ticket",
    "invoice" => "Facture"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :expense_report, inverse_of: :expense_lines
  belongs_to :general_account, optional: true
  belongs_to :team, optional: true
  belongs_to :analytic_account, optional: true

  has_one_attached :receipt

  monetize :amount_cents

  validates :spent_on, :label, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :doc_kind, inclusion: { in: DOC_KINDS }, allow_blank: true
  validates :general_account, presence: { message: "est obligatoire — c'est lui qui porte la charge" }
  validate :report_still_editable

  before_destroy :refuse_when_report_frozen

  scope :ordered, -> { order(:position, :spent_on, :id) }
  scope :chronological, -> { order(:spent_on, :id) }

  def doc_kind_label = DOC_KIND_LABELS[doc_kind]

  # Le montant tel qu'il se tape : « 24,90 ». Money-rails accepte déjà `amount=`,
  # mais pas la virgule décimale d'un clavier belge — et c'est comme ça que la
  # compta tape. Une saisie refusée pour une virgule serait absurde.
  def amount_in_euros
    # Zéro se lit « rien saisi » : un « 0,00 » prérempli dans une ligne vierge
    # est un champ qu'il faut effacer avant de taper, à chaque ligne.
    return nil if amount_cents.to_i.zero?

    format("%.2f", amount_cents / 100.0).tr(".", ",")
  end

  def amount_in_euros=(value)
    self.amount_cents = value.present? ? Monetize.parse(value.to_s.tr(",", ".")).cents : nil
  end

  private

  # `validate` ne couvre pas la suppression : sans ce garde-fou, retirer une
  # ligne d'une note déjà comptabilisée passerait sans un mot.
  def refuse_when_report_frozen
    return if expense_report.blank? || expense_report.editable?

    errors.add(:base, "La note n'est plus modifiable — sa pièce comptable existe.")
    throw(:abort)
  end

  # Une ligne qui bougerait sous une note déjà comptabilisée ferait diverger le
  # total de son écriture sans que rien ne le dise. Le même garde-fou que sur
  # `CashAllocation`, pour la même raison.
  def report_still_editable
    return if expense_report.blank? || expense_report.editable?
    return if expense_report.status_was == "recorded"

    errors.add(:base,
               "La note #{expense_report.reference.presence || "##{expense_report.id}"} " \
               "n'est plus modifiable — sa pièce comptable existe.")
  end
end
