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

  # Chaque appel purge aussi les sels des jours passés : un sel ne survit pas
  # au premier passage du lendemain (visite du site ou ouverture du tableau de
  # bord). Une sauvegarde de la base faite dans la journée contient, elle, le
  # sel du jour.
  def self.for(day)
    purge_before!(day)
    where(day: day).pick(:salt) || rotate!(day)
  end

  def self.purge_before!(day)
    where(day: ...day).delete_all
  end

  def self.rotate!(day)
    create!(day: day, salt: SecureRandom.hex(32)).salt
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Deux premières visites simultanées : l'autre requête a gagné.
    where(day: day).pick(:salt)
  end
end
