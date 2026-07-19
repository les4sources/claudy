module Stays
  # Fusion de séjours (epic #81). Rapatrie TOUTE la composition d'un ou plusieurs
  # séjours SOURCES sur un séjour CIBLE (le « survivant »), puis soft-delete les
  # sources vidées. Sert l'assainissement de l'historique : des dizaines de
  # doublons legacy (Tally / OTA / imports) à recoller à la main.
  #
  # Ce qui migre vers la cible (chaque déplacement est tracé par PaperTrail) :
  #   - les `StayItem` (hébergement / espace / camping / van) ;
  #   - les `ExperienceBooking` (activités) ;
  #   - les `MealOrder` (repas) ;
  #   - les `Payment` ancrés DIRECTEMENT sur le séjour (`payments.stay_id`). Les
  #     paiements ancrés via le booking suivent automatiquement leur StayItem.
  #
  # Règles fixes :
  #   - le CLIENT conservé est celui de la CIBLE (comme Customers::MergeService,
  #     « la cible gagne ») ;
  #   - dates recalculées en UNION (min arrivée / max départ) via
  #     `recompute_aggregates!` — même source de vérité que partout ;
  #   - total et statut de paiement recalculés depuis la composition rapatriée.
  #
  # `Stays::MergePreview` calcule le MÊME résultat en dry-run (aperçu serveur) ;
  # un test de cohérence garantit que preview == fusion réelle.
  class MergeService < ServiceBase
    attr_reader :target, :sources, :merged_count

    def initialize(target:, sources:)
      @target = target
      @sources = Array(sources).compact
      @merged_count = 0
    end

    def run
      return set_error_message("Séjour cible manquant.") && false if target.nil?
      return set_error_message("Sélectionne au moins deux séjours à fusionner.") && false if sources.empty?
      return set_error_message("La cible ne peut pas figurer parmi les sources.") && false if sources.any? { |s| s.id == target.id }

      catch_error(context: { target: target.id, sources: sources.map(&:id) }) do
        ActiveRecord::Base.transaction do
          sources.each { |source| absorb!(source) }

          target.reload
          target.recompute_aggregates! # total + dates (union) — source unique de vérité
          target.set_payment_status    # statut de paiement d'après l'encaissé rapatrié

          true
        end
      end
    end

    private

    # Rapatrie toute la composition d'un séjour source sur la cible, puis le
    # soft-delete une fois vidé. Chaque `update!` est tracé (PaperTrail).
    def absorb!(source)
      source.stay_items.each         { |item| item.update!(stay_id: target.id) }
      source.experience_bookings.each { |eb|  eb.update!(stay_id: target.id) }
      source.meal_orders.each        { |meal| meal.update!(stay_id: target.id) }
      # Paiements ancrés directement sur le séjour (issue #26) : à ré-ancrer.
      # Ceux liés via le booking suivent leur StayItem sans action.
      Payment.where(stay_id: source.id).find_each { |payment| payment.update!(stay_id: target.id) }

      source.reload
      source.soft_delete!(validate: false)
      @merged_count += 1
    end
  end
end
