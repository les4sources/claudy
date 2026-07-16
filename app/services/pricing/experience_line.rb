module Pricing
  # Source de vérité UNIQUE du tarif d'une activité (Experience) — epic #55,
  # Phase 1. Centralise la formule « forfait fixe + €/pers » et le rendu du
  # barème, jusqu'ici dupliqués entre `PricingModel#experience_lines`
  # (calcul) et la vue `activities.html.slim` (libellé). Tout consommateur
  # (moteur de devis, `ExperienceBooking#price_cents`, vue) passe désormais
  # par ici : un seul endroit à corriger si le barème évolue.
  #
  # Tous les montants sont en cents et TVAC ("pas de TVA en plus").
  module ExperienceLine
    module_function

    # Montant TVAC d'une réservation d'activité : forfait fixe (facturé une
    # fois) + prix par personne × nombre de participants.
    def amount_cents(experience, participants:)
      experience.fixed_price_cents.to_i + experience.price_cents.to_i * participants.to_i
    end

    # Libellé du barème affiché dans le funnel, reproduisant à l'identique les
    # 4 variantes historiques de la vue :
    #   - forfait fixe + €/pers  → "40 € + 15 €/pers"
    #   - €/pers seul            → "15 €/pers"
    #   - forfait fixe seul      → "40 €"
    #   - ni l'un ni l'autre     → "Gratuit"
    def rate_label(experience)
      fixed = experience.fixed_price_cents.to_i
      per   = experience.price_cents.to_i

      if fixed.positive? && per.positive?
        "#{format_eur(fixed)} + #{format_eur(per)}/pers"
      elsif per.positive?
        "#{format_eur(per)}/pers"
      elsif fixed.positive?
        format_eur(fixed)
      else
        "Gratuit"
      end
    end

    # Rendu monétaire aligné sur la vue : "290 €" (unité suffixée, sans
    # décimale). Passe par ActiveSupport pour rester utilisable hors contexte
    # de vue (service, modèle).
    def format_eur(cents)
      ActiveSupport::NumberHelper.number_to_currency(
        cents / 100.0, unit: "€", format: "%n %u", precision: 0
      )
    end
  end
end
