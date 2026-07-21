module Pricing
  # Façade de lecture des tarifs paramétrés en base (issue #124).
  #
  # `Pricing::Catalog` interroge ce module AVANT ses constantes : si la clé
  # existe en base, c'est elle qui gagne ; sinon on retombe sur la constante
  # codée. Tant que `rake rates:seed_from_catalog` n'a pas tourné, ou tant que
  # la table reflète fidèlement le catalogue, aucun devis ne change.
  #
  # Le chargement est mémoïsé pour la durée de la requête (via
  # `ActiveSupport::CurrentAttributes`, remis à zéro par Rails à chaque requête
  # et à chaque job) : un devis composite ne fait donc qu'UN seul SELECT.
  module Rates
    module_function

    # Montant en cents pour `key`, ou nil si la clé n'est pas paramétrée.
    def cents(key)
      lookup[key.to_s]
    end

    # Montant en cents, avec repli explicite sur la valeur codée.
    def cents_or(key, fallback)
      cents(key) || fallback
    end

    # Valeur décimale (0.5 pour 50 %) d'une clé stockée en `percent`.
    def rate_or(key, fallback)
      value = cents(key)
      value.nil? ? fallback : value / 100.0
    end

    def lookup
      Pricing::Rates::Store.lookup ||= load_lookup
    end

    def reset!
      Pricing::Rates::Store.lookup = nil
    end

    def load_lookup
      return {} unless table_available?

      Rate.pluck(:key, :amount_cents).to_h
    end

    def table_available?
      Rate.table_exists?
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      false
    end

    # Porte-mémoire remis à zéro par Rails à chaque requête / job.
    class Store < ActiveSupport::CurrentAttributes
      attribute :lookup
    end
  end
end
