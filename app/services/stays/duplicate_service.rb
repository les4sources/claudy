module Stays
  # Duplication de séjour (epic #81, Phase 7).
  #
  # CHOIX D'ARCHITECTURE — pas de clone DB instantané. La duplication NE crée
  # RIEN en base : elle renvoie un `Reservations::Draft` prérempli depuis le
  # séjour source, destiné à alimenter le formulaire NEW. L'admin choisit de
  # NOUVELLES dates puis soumet — c'est la création normale (`Reservations::
  # Builder`) qui persiste. Pourquoi repasser par le form plutôt que cloner
  # directement :
  #   - un clone immédiat aux MÊMES dates surbookerait l'hébergement ET les
  #     espaces (le veto de dispo compte les Reservation/SpaceReservation) ;
  #   - les paiements déjà encaissés sur la source n'ont pas eu lieu sur le clone ;
  #   - un prix imposé figé ne vaut plus pour un séjour à d'autres dates.
  # On délègue donc la décision de dates/prix à l'admin, via le form.
  #
  # COPIÉ : client + composition (hébergement/mode chambres, espaces + facturation,
  # camping, van, repas, activités réutilisables) — tout ce que
  # `Stays::DraftReconstructor` sait reconstruire.
  # EXCLU :
  #   - toutes les dates (séjour ET éléments datés espace/repas) → re-planification
  #     forcée, anti-surbooking ;
  #   - les paiements → jamais reconstruits par le Draft, et le canal admin n'en
  #     crée aucun à la création ;
  #   - le prix imposé → absent du Draft ; le devis B2C se recalcule et l'admin le
  #     re-saisira si besoin.
  # Le statut du séjour dupliqué reste « pending » (défaut du form NEW).
  class DuplicateService
    def self.call(stay:)
      new(stay: stay).call
    end

    def initialize(stay:)
      @stay = stay
    end

    def call
      draft = DraftReconstructor.new(@stay).to_draft
      blank_all_dates!(draft)
      draft
    end

    private

    # Vide TOUTES les dates du draft : niveau séjour (arrivée/départ) et niveau
    # élément (espaces, repas). L'admin re-date l'ensemble depuis le form.
    def blank_all_dates!(draft)
      draft.arrival_date   = nil
      draft.departure_date = nil
      draft.halls = strip_dates(draft.halls)
      draft.meals = strip_dates(draft.meals)
    end

    def strip_dates(rows)
      Array(rows).map do |row|
        row = row.symbolize_keys if row.respond_to?(:symbolize_keys)
        row.merge(date: nil)
      end
    end
  end
end
