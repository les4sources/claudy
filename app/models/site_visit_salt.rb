# Le sel aléatoire d'une journée, qui entre dans l'empreinte des visiteurs du
# site (voir `SiteStats::Tracker`). Un seul sel vivant à la fois : celui du jour
# est créé à la première visite, et ceux des jours passés sont supprimés au
# même moment. Pas de tâche planifiée — la prod n'a pas de file de jobs.
# == Schema Information
#
# Table name: site_visit_salts
#
#  id         :bigint           not null, primary key
#  day        :date             not null
#  salt       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_site_visit_salts_on_day  (day) UNIQUE
#
class SiteVisitSalt < ApplicationRecord
  validates :day, presence: true, uniqueness: true
  validates :salt, presence: true

  def self.for(day)
    where(day: day).pick(:salt) || rotate!(day)
  end

  def self.rotate!(day)
    where.not(day: day).delete_all
    create!(day: day, salt: SecureRandom.hex(32)).salt
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Deux premières visites simultanées : l'autre requête a gagné.
    where(day: day).pick(:salt)
  end
end
