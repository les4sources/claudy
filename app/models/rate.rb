# Tarif paramétrable en base (issue #124).
#
# Une ligne = une clé du barème (ex. `camping.tente_per_person_night`) et son
# montant. `Pricing::Catalog` lit cette table EN PREMIER et retombe sur ses
# constantes codées quand la clé manque — la base ne fait donc jamais varier un
# prix tant qu'elle n'a pas été seedée (`rake rates:seed_from_catalog`).
#
# `unit` distingue les montants monétaires (`cents`, l'écrasante majorité) des
# valeurs exprimées en pourcentage (`percent`, ex. le taux d'acompte par
# défaut). L'écran d'édition rend les deux différemment.
class Rate < ApplicationRecord
  UNITS = %w[cents percent].freeze

  # Regroupement d'affichage de l'écran Paramètres > Tarifs, dans l'ordre.
  # Chaque entrée : libellé du groupe => préfixes de clés qui y tombent.
  #
  # « Sourciers » (issue #156) est déclaré APRÈS « Repas » : le groupe d'une clé
  # est le premier dont un préfixe matche, donc les clés `meal.` existantes
  # restent dans « Repas », quoi qu'on ajoute ensuite.
  GROUPS = {
    "Hébergements"  => %w[lodging.],
    "Salles"        => %w[hall. hall_weekend.],
    "Camping & van" => %w[camping. van. terrace. hamac.],
    "Repas"         => %w[meal. pizza_party.],
    "Sourciers"     => %w[bar. grocery. pot. dome. pet.],
    "Coworking"     => %w[coworking.]
  }.freeze

  OTHER_GROUP = "Divers".freeze

  has_paper_trail

  # Barèmes datés (#156). `amount_cents` reste le miroir de la version qui
  # couvre aujourd'hui : la lecture non datée ne touche jamais cette table.
  has_many :rate_versions, dependent: :destroy, inverse_of: :rate

  validates :key, presence: true, uniqueness: true
  validates :amount_cents,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :unit, inclusion: { in: UNITS }

  scope :ordered, -> { order(key: :asc) }

  def percent? = unit == "percent"

  def group
    GROUPS.each do |name, prefixes|
      return name if prefixes.any? { |prefix| key.to_s.start_with?(prefix) }
    end
    OTHER_GROUP
  end

  # Version qui couvre `date`, ou nil si la période n'est couverte par aucune.
  # Passe par les versions déjà chargées quand elles le sont (écran Tarifs).
  def version_on(date)
    if rate_versions.loaded?
      rate_versions.find { |version| version.covers?(date) }
    else
      rate_versions.covering(date).first
    end
  end

  def current_version = version_on(Date.current)

  # Historique affiché sur l'écran Tarifs : la plus récente en tête.
  def versions_history
    rate_versions.loaded? ? rate_versions.sort_by(&:active_from).reverse
                          : rate_versions.most_recent_first.to_a
  end

  # Tous les tarifs groupés pour l'écran d'édition, groupes dans l'ordre déclaré.
  def self.grouped
    by_group = ordered.includes(:rate_versions).group_by(&:group)
    (GROUPS.keys + [OTHER_GROUP]).filter_map do |name|
      rates = by_group[name]
      [name, rates] if rates.present?
    end
  end

  # Valeur affichable/éditable : euros pour `cents`, pourcentage pour `percent`.
  def amount
    percent? ? amount_cents : amount_cents / 100.0
  end
end
