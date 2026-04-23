# == Schema Information
#
# Table name: decisions
#
#  id              :bigint           not null, primary key
#  title           :string           not null
#  summary         :string           not null
#  taken_at        :date             not null
#  recorded_by_id  :bigint           not null
#  gathering_id    :bigint
#  agenda_item_id  :bigint
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  deleted_at      :datetime
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
