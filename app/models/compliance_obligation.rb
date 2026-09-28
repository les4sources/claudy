# Une obligation comptable ou légale d'une entité (Michael, 2026-09-28) : la
# RÈGLE, écrite une fois — « la SRL déclare sa TVA chaque trimestre, le 20 du
# mois qui suit ».
#
# Dans Notion, chaque trimestre se recopiait à la main, et une copie oubliée
# était une déclaration oubliée. Ici la règle génère ses échéances
# (`ComplianceDeadlines::Generate`) : on ne saisit plus que ce qui s'écarte de
# la règle — une date avancée, une note, une preuve.
#
# La récurrence tient en trois champs : la fréquence, la PREMIÈRE échéance à
# suivre, et la période que chaque échéance couvre. La TVA d'avril couvre le
# trimestre PRÉCÉDENT (T1) ; le précompte immobilier d'octobre couvre l'année
# EN COURS. Les suivantes se déduisent de la première par pas de 1, 3 ou 12
# mois — toujours depuis la première, pour qu'un 31 janvier ne dérive pas en
# 28 le mois suivant puis en 28 pour toujours.
# == Schema Information
#
# Table name: compliance_obligations
#
#  id                  :bigint           not null, primary key
#  active              :boolean          default(TRUE), not null
#  covers              :string           default("previous"), not null
#  deleted_at          :datetime
#  ends_on             :date
#  first_due_on        :date             not null
#  frequency           :string           default("yearly"), not null
#  instructions        :text
#  payment             :boolean          default(FALSE), not null
#  title               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  legal_entity_id     :bigint           not null
#  responsible_user_id :bigint
#
# Indexes
#
#  index_compliance_obligations_on_deleted_at           (deleted_at)
#  index_compliance_obligations_on_entity_and_title     (legal_entity_id,title) UNIQUE WHERE (deleted_at IS NULL)
#  index_compliance_obligations_on_legal_entity_id      (legal_entity_id)
#  index_compliance_obligations_on_responsible_user_id  (responsible_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (responsible_user_id => users.id)
#
class ComplianceObligation < ApplicationRecord
  FREQUENCIES = %w[once monthly quarterly yearly].freeze
  FREQUENCY_LABELS = {
    "once" => "Une seule fois",
    "monthly" => "Chaque mois",
    "quarterly" => "Chaque trimestre",
    "yearly" => "Chaque année"
  }.freeze
  FREQUENCY_MONTHS = { "monthly" => 1, "quarterly" => 3, "yearly" => 12 }.freeze

  COVERS = %w[previous current].freeze
  COVERS_LABELS = {
    "previous" => "la période précédente (ex. TVA d'avril → T1)",
    "current" => "la période en cours (ex. précompte d'octobre → l'année)"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  # Facultatif : sans responsable, les rappels vont aux destinataires comptables
  # déclarés dans les réglages — la même liste que les validations d'achats.
  belongs_to :responsible_user, class_name: "User", optional: true
  has_many :compliance_deadlines, dependent: :restrict_with_error

  validates :title, presence: true, uniqueness: { scope: :legal_entity_id, conditions: -> { where(deleted_at: nil) } }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :covers, inclusion: { in: COVERS }
  validates :first_due_on, presence: true
  validate :ends_after_first_due

  scope :ordered, -> { order(:title) }
  scope :actives, -> { where(active: true) }

  def frequency_label = FREQUENCY_LABELS.fetch(frequency, frequency)
  def once? = frequency == "once"

  # Qui reçoit les rappels. Une liste, parce que le repli en est une.
  def reminder_recipients
    return [responsible_user] if responsible_user

    NotificationSettingsController.accounting_users.to_a
  end

  # Les échéances de la règle jusqu'à `horizon` inclus, sous la forme
  # `[period_start, due_on]`. Rien n'est écrit : c'est le calendrier théorique,
  # que le générateur compare à ce qui existe.
  def schedule_through(horizon)
    return [] if first_due_on.blank?
    return first_due_on <= horizon ? [[first_due_on, first_due_on]] : [] if once?

    step = FREQUENCY_MONTHS.fetch(frequency)
    last = [horizon, ends_on].compact.min
    dates = []
    index = 0
    loop do
      due_on = first_due_on >> (index * step)
      break if due_on > last

      dates << [period_start_for(due_on), due_on]
      index += 1
    end
    dates
  end

  # Le libellé de la période couverte : « T1 2026 », « 2025 », « août 2026 ».
  def period_label(period_start)
    case frequency
    when "monthly" then I18n.l(period_start, format: "%B %Y")
    when "quarterly" then "T#{((period_start.month - 1) / 3) + 1} #{period_start.year}"
    when "yearly" then period_start.year.to_s
    end
  end

  private

  def period_start_for(due_on)
    step = FREQUENCY_MONTHS.fetch(frequency)
    anchor = covers == "previous" ? due_on << step : due_on
    case frequency
    when "monthly" then anchor.beginning_of_month
    when "quarterly" then anchor.beginning_of_quarter
    when "yearly" then anchor.beginning_of_year
    end
  end

  def ends_after_first_due
    return if ends_on.blank? || first_due_on.blank? || ends_on >= first_due_on

    errors.add(:ends_on, "doit suivre la première échéance")
  end
end
