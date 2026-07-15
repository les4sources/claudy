module Customers
  # Politique unique d'upsert d'un Customer à partir d'un email (epic #26,
  # Phase 3). Extrait la logique jusqu'ici enfermée dans
  # LegacyBookingMigration::Runner#upsert_customer_for pour qu'admin/OTA et
  # futurs importeurs partagent EXACTEMENT la même règle « même email → même
  # Customer ».
  #
  # Règle déterministe (cf. Customer.exploitable_email?) :
  #   - email exploitable (format valide, y compris relais OTA) → on retrouve le
  #     Customer vivant portant cet email normalisé (lowercase, citext) ou on en
  #     crée un ;
  #   - email inexploitable (vide/invalide) → rattachement au Customer fourre-tout
  #     CATCH_ALL_EMAIL, jamais de perte.
  #
  # On ne recâble PAS Runner sur ce service dans cette PR (Runner est testé, a
  # tourné en prod et gère ses compteurs/cache de rapport). Ce service est le
  # foyer unique pour tout NOUVEL appelant.
  class UpsertByEmail
    def self.call(email:, attrs: {})
      new(email: email, attrs: attrs).call
    end

    def initialize(email:, attrs: {})
      @raw_email = email
      @attrs = attrs || {}
    end

    def call
      if Customer.exploitable_email?(@raw_email)
        upsert_real_customer
      else
        catch_all_customer
      end
    end

    private

    def upsert_real_customer
      email = Customer.normalize_email(@raw_email)
      # Index unique partiel sur les lignes vivantes : un email exploitable ne
      # peut désigner qu'un seul Customer vivant. On le réutilise donc plutôt que
      # d'en créer un doublon (idempotence par email).
      existing = Customer.find_by(email: email)
      return existing if existing

      persist(@attrs.merge(email: email))
    end

    def catch_all_customer
      existing = Customer.find_by(email: Customer::CATCH_ALL_EMAIL)
      return existing if existing

      persist(
        email: Customer::CATCH_ALL_EMAIL,
        first_name: "Client",
        last_name: "Les 4 Sources",
        customer_type: "individual",
        language: "fr"
      )
    end

    # Les données admin/OTA peuvent être incomplètes (pas de nom, pas de langue…)
    # sans que cela doive jamais empêcher la création du séjour. La clé est
    # l'email, dont l'unicité vivante est déjà garantie par le find_by ci-dessus.
    # On persiste donc en contournant les validations non structurantes, comme le
    # fait Runner pour la donnée legacy.
    def persist(attributes)
      customer = Customer.new(attributes)
      customer.save!(validate: false)
      customer
    end
  end
end
