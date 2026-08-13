# == Schema Information
#
# Table name: agenda_items
#
#  id           :bigint           not null, primary key
#  completed    :boolean          default(FALSE), not null
#  deleted_at   :datetime
#  list         :integer          default(0), not null
#  position     :integer          default(0), not null
#  title        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  author_id    :bigint           not null
#  carrier_id   :bigint
#  gathering_id :bigint           not null
#
# Indexes
#
#  index_agenda_items_on_author_id                           (author_id)
#  index_agenda_items_on_carrier_id                          (carrier_id)
#  index_agenda_items_on_gathering_id                        (gathering_id)
#  index_agenda_items_on_gathering_id_and_list_and_position  (gathering_id,list,position)
#  index_agenda_items_on_gathering_id_and_position           (gathering_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (author_id => humans.id)
#  fk_rails_...  (carrier_id => humans.id)
#  fk_rails_...  (gathering_id => gatherings.id)
#
class AgendaItem < ApplicationRecord
  include PublicActivity::Model
  tracked owner: Proc.new { |controller, _model| controller.current_user rescue nil }

  belongs_to :gathering
  belongs_to :author, class_name: "Human"
  belongs_to :carrier, class_name: "Human", optional: true
  has_many :decisions, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description
  has_many_attached :attachments

  # Ordered lists of agenda points. Order of declaration = display order.
  enum :list, { atelier: 0, informations: 1, triage: 2, decisions: 3 }

  LIST_LABELS = {
    "atelier" => "Atelier",
    "informations" => "Informations",
    "triage" => "Triage",
    "decisions" => "Décisions"
  }.freeze

  # Order used when offering the list choice in the add/edit form (distinct from
  # the display order on the gathering page, which follows the enum).
  LIST_FORM_ORDER = %w[informations triage decisions atelier].freeze

  def self.list_label(key)
    LIST_LABELS.fetch(key.to_s, key.to_s.humanize)
  end

  validates :title, presence: true

  scope :ordered, -> { order(position: :asc, id: :asc) }
  scope :pending, -> { where(completed: false) }

  before_create :assign_next_position

  private

  # Position is scoped to (gathering, list): each of the four lists has its own
  # ordering. Recomputed when an item moves to another list (see #reorder).
  def assign_next_position
    return if position.present? && position.positive?
    max = gathering.agenda_items.where(list: list).maximum(:position) || -1
    self.position = max + 1
  end
end
