# == Schema Information
#
# Table name: decisions
#
#  id             :bigint           not null, primary key
#  deleted_at     :datetime
#  summary        :string           not null
#  taken_at       :date             not null
#  title          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  agenda_item_id :bigint
#  gathering_id   :bigint
#  recorded_by_id :bigint           not null
#
# Indexes
#
#  index_decisions_on_agenda_item_id  (agenda_item_id)
#  index_decisions_on_gathering_id    (gathering_id)
#  index_decisions_on_recorded_by_id  (recorded_by_id)
#  index_decisions_on_taken_at        (taken_at)
#
# Foreign Keys
#
#  fk_rails_...  (agenda_item_id => agenda_items.id) ON DELETE => nullify
#  fk_rails_...  (gathering_id => gatherings.id) ON DELETE => nullify
#  fk_rails_...  (recorded_by_id => humans.id)
#
class Decision < ApplicationRecord
  include PublicActivity::Model
  tracked owner: Proc.new { |controller, _model| controller.current_user rescue nil }

  belongs_to :recorded_by, class_name: "Human"
  belongs_to :gathering, optional: true
  belongs_to :agenda_item, optional: true

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :body

  validates :title, :summary, :taken_at, presence: true

  scope :recent, -> { order(taken_at: :desc, id: :desc) }

  def self.search(query)
    return all if query.blank?
    like = "%#{sanitize_sql_like(query)}%"
    joins("LEFT JOIN action_text_rich_texts art ON art.record_id = decisions.id AND art.record_type = 'Decision' AND art.name = 'body'")
      .where("decisions.title ILIKE :q OR decisions.summary ILIKE :q OR art.body ILIKE :q", q: like)
      .distinct
  end
end
