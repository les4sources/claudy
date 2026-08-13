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
    #
    # Avec `on:` (issue #156), la lecture devient historique : c'est le montant
    # de la version dont la période couvre cette date, ou nil si aucune ne la
    # couvre. Sans `on:`, RIEN ne change — même unique SELECT sur `rates`, même
    # mémoïsation : le chemin du devis ne paie pas la dimension temporelle.
    def cents(key, on: nil)
      return lookup[key.to_s] if on.nil?

      dated_lookup(on)[key.to_s]
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

    # Un lookup par date demandée, mémoïsé comme le lookup courant : rejouer
    # tout un décompte historique ne fait donc qu'UN SELECT par date traitée.
    def dated_lookup(date)
      store = (Pricing::Rates::Store.dated ||= {})
      store[date] ||= load_dated_lookup(date)
    end

    def reset!
      Pricing::Rates::Store.lookup = nil
      Pricing::Rates::Store.dated = nil
    end

    def load_lookup
      return {} unless table_available?

      Rate.pluck(:key, :amount_cents).to_h
    end

    def load_dated_lookup(date)
      return {} unless table_available? && versions_table_available?

      RateVersion.covering(date)
                 .joins(:rate)
                 .pluck("rates.key", "rate_versions.amount_cents")
                 .to_h
    end

    def table_available?
      Rate.table_exists?
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      false
    end

    def versions_table_available?
      RateVersion.table_exists?
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      false
    end

    # Porte-mémoire remis à zéro par Rails à chaque requête / job.
    class Store < ActiveSupport::CurrentAttributes
      attribute :lookup
      attribute :dated
    end
  end
end
