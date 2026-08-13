# == Schema Information
#
# Table name: events
#
#  id                 :bigint           not null, primary key
#  attendees          :integer
#  deleted_at         :datetime
#  ends_at            :datetime
#  name               :string
#  notes              :text
#  sales_amount_cents :integer
#  starts_at          :datetime
#  status             :string
#  url                :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  event_category_id  :bigint           not null
#
# Indexes
#
#  index_events_on_event_category_id  (event_category_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_category_id => event_categories.id)
#
class Event < ApplicationRecord
  # PublicActivity
  include PublicActivity::Model
  tracked owner: Proc.new{ |controller, model| controller.current_user rescue nil }

  belongs_to :event_category

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :sales_amount_cents, allow_nil: true

  has_rich_text :notes

  validates :name,
            presence: true
  validates :starts_at_date,
            presence: { message: "Veuillez spécifier une date de début" }
  validates :ends_at_date,
            presence: { message: "Veuillez spécifier une date de fin" }

  attr_accessor :starts_at_date, :starts_at_time, :ends_at_date, :ends_at_time

  by_star_field :starts_at, :ends_at
end
