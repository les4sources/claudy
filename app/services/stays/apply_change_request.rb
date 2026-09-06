module Stays
  # Application d'une demande de modification approuvée par l'équipe (#133).
  #
  # C'est le SEUL endroit qui touche au séjour : tant que la demande est
  # `pending`, rien n'a bougé. L'application passe par `Stays::AdminUpdater`
  # (réutilisé tel quel), puis recalcule le statut de paiement — donc le solde
  # exigible absorbe automatiquement un delta positif.
  #
  # L'IBAN et la consigne des 10 jours sont recopiés dans la NOTE INTERNE :
  # le remboursement est manuel, il faut que l'info vive là où l'équipe la lit.
  class ApplyChangeRequest
    attr_reader :error_message

    def initialize(change_request:, user: nil, force_availability: false)
      @change_request = change_request
      @user = user
      @force_availability = force_availability
    end

    def run
      stay = @change_request.stay
      draft = refresh_untouched_composition(@change_request.proposed_draft, stay)

      # Re-vérification de dispo à la validation : le monde a pu bouger depuis
      # la soumission du client. Le forçage reste possible côté équipe.
      unless @force_availability || Stays::LodgingAvailability.call(stay: stay, draft: draft)
        @error_message = "Ces dates ne sont plus disponibles pour cet hébergement."
        return false
      end

      updater = Stays::AdminUpdater.new(
        stay: stay,
        draft: draft,
        skip_availability: true,
        # PRIX PRÉSERVÉ : `new_total_cents` = prix existant du séjour + delta
        # (jamais une recote complète — cf. StayChangeRequestsController). On
        # l'impose pour qu'un séjour à prix historique/négocié garde son prix
        # à l'approbation d'une demande qui ne change rien (delta 0).
        price_override_cents: @change_request.new_total_cents,
        user: @user
      )

      unless updater.run
        @error_message = updater.error_message(default: "La modification n'a pas pu être appliquée.")
        return false
      end

      ActiveRecord::Base.transaction do
        if @change_request.refund_expected?
          append_refund_note!(stay)
          stay.save!
        end
        # `set_payment_status` persiste lui-même : le solde exigible absorbe
        # le delta positif, et un séjour retombé sous le déjà-payé passe `paid`.
        stay.set_payment_status
        @change_request.update!(status: "approved")
      end

      true
    end

    private

    # Le snapshot du client date de sa SOUMISSION ; l'approbation peut venir
    # des jours plus tard. Entre les deux, l'équipe a pu ajouter un buffet,
    # corriger des convives, poser une activité. Rejouer le snapshot tel quel
    # annulerait tout ça en silence (`reconcile_meals!` annule ce qui manque au
    # draft) et remettrait des validations de cuisine en attente pour un
    # changement que personne n'a demandé.
    #
    # Le formulaire client ne porte ni les repas, ni les activités, ni la
    # terrasse : on les relit donc du séjour au moment de l'appliquer, pas au
    # moment de la demande. Ce que le client a réellement demandé — dates,
    # hébergement, occupants — vient bien de son snapshot.
    def refresh_untouched_composition(draft, stay)
      current = Stays::DraftReconstructor.call(stay)
      draft.meals       = current.meals
      draft.experiences = current.experiences
      draft.terrasses   = current.terrasses
      draft
    end

    def append_refund_note!(stay)
      line = "Remboursement à effectuer — IBAN #{@change_request.refund_iban}. " \
             "#{StayChangeRequest::REFUND_NOTICE}"
      stay.notes = [stay.notes.presence, line].compact.join("\n")
    end
  end
end
