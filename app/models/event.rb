class Event < ApplicationRecord
  belongs_to :event_category

  validates :name,
            presence: true
  validates :starts_at_date,
            presence: { message: "Veuillez spécifier une date de début" }
  validates :ends_at_date,
            presence: { message: "Veuillez spécifier une date de fin" }

  attr_accessor :starts_at_date, :starts_at_time, :ends_at_date, :ends_at_time

  by_star_field :starts_at, :ends_at
end
