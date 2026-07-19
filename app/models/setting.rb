# == Schema Information
#
# Table name: settings
#
#  id         :bigint           not null, primary key
#  key        :string           not null
#  value      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Magasin clé/valeur pour les paramètres globaux du domaine ajustables SANS
# redéploiement (issue #78). Chaque paramètre est une ligne `key`/`value` ;
# absence de ligne = on retombe sur le défaut fourni par l'appelant. Les valeurs
# sont stockées en texte et converties à la lecture (cf. `.integer`).
#
# Lecture typée :
#   Setting.integer("camping_total_capacity", default: 30)
# Écriture (console ou futur écran admin) :
#   Setting.set("camping_total_capacity", 45)
class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Valeur brute (String) d'un paramètre, ou nil si absent.
  def self.[](key)
    find_by(key: key.to_s)&.value
  end

  # Valeur entière d'un paramètre, ou `default` si absent/illisible.
  def self.integer(key, default: nil)
    raw = self[key]
    return default if raw.blank?

    Integer(raw, exception: false) || default
  end

  # Crée ou met à jour un paramètre. Renvoie l'enregistrement.
  def self.set(key, value)
    record = find_or_initialize_by(key: key.to_s)
    record.update!(value: value.to_s)
    record
  end
end
