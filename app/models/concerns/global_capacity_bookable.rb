# Disponibilité à CAPACITÉ GLOBALE pour les réservables « plein air » du terrain
# (camping, van/camping-car) — epic #66, Phase 3.
#
# Contrairement aux `Space` (capacité par ressource nommée), ces réservables
# partagent une SEULE capacité globale du domaine (pas d'emplacements nommés,
# décision figée Michael 2026-07-18). Le modèle hôte fournit :
#   - une constante `TOTAL_CAPACITY` (capacité totale, en unités du modèle) ;
#   - `#capacity_units` : le nombre d'unités que CETTE réservation consomme
#     (personnes pour le camping, véhicules pour le van).
#
# Une réservation occupe chaque NUIT de la fenêtre [from_date, to_date). Une nuit
# `d` est couverte si `from_date <= d < to_date`. La dispo est vérifiée nuit par
# nuit : pour chaque nuit demandée, (unités déjà confirmées) + (unités demandées)
# ne doit pas dépasser `TOTAL_CAPACITY`. Seules les réservations `confirmed`
# comptent contre la capacité (comme `Space#booked_on?`).
module GlobalCapacityBookable
  extend ActiveSupport::Concern

  included do
    scope :confirmed, -> { where(status: "confirmed") }
    # Réservations couvrant la nuit `date` (from <= date < to).
    scope :covering, ->(date) { where("from_date <= ? AND to_date > ?", date, date) }
  end

  class_methods do
    # Capacité totale effective du domaine pour ce réservable. Lue depuis la
    # config (`Setting`) quand le modèle déclare une `CAPACITY_SETTING_KEY`
    # (issue #78 : ajustable sans redéploiement), sinon la constante `TOTAL_CAPACITY`.
    # Le défaut reste `TOTAL_CAPACITY` tant que le paramètre n'est pas renseigné.
    def total_capacity
      return self::TOTAL_CAPACITY unless const_defined?(:CAPACITY_SETTING_KEY)

      Setting.integer(self::CAPACITY_SETTING_KEY, default: self::TOTAL_CAPACITY)
    end

    # Unités déjà CONFIRMÉES pour la nuit `date`, en excluant éventuellement une
    # réservation donnée (utile à l'édition d'un réservable existant).
    def units_reserved_on(date, excluding_id: nil)
      scope = confirmed.covering(date)
      scope = scope.where.not(id: excluding_id) if excluding_id
      scope.sum(capacity_units_column)
    end

    # Unités restantes pour la nuit `date`.
    def remaining_on(date, excluding_id: nil)
      [total_capacity - units_reserved_on(date, excluding_id: excluding_id), 0].max
    end

    # Première nuit en conflit de capacité pour une demande, ou nil si tout passe.
    # `from`/`to` = fenêtre [arrivée, départ) ; `units` = unités demandées.
    def capacity_conflict_date(units:, from:, to:, excluding_id: nil)
      return nil if units.to_i < 1 || from.blank? || to.blank?

      cap = total_capacity
      (from...to).find do |date|
        units_reserved_on(date, excluding_id: excluding_id) + units.to_i > cap
      end
    end

    # Colonne portant les unités consommées — surchargée par chaque modèle.
    def capacity_units_column
      raise NotImplementedError, "#{name} must define .capacity_units_column"
    end
  end
end
