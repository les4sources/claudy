# == Schema Information
#
# Table name: events
#
#  id                :bigint           not null, primary key
#  name              :string
#  event_category_id :bigint           not null
#  starts_at         :datetime
#  ends_at           :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  deleted_at        :datetime
#  url               :string
#
class Event < ApplicationRecord
  belongs_to :event_category

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :name,
            presence: true
  validates :starts_at_date,
            presence: { message: "Veuillez spécifier une date de début" }
  validates :ends_at_date,
            presence: { message: "Veuillez spécifier une date de fin" }

  attr_accessor :starts_at_date, :starts_at_time, :ends_at_date, :ends_at_time

  by_star_field :starts_at, :ends_at
end
