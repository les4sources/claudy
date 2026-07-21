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
      draft = @change_request.proposed_draft

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

    def append_refund_note!(stay)
      line = "Remboursement à effectuer — IBAN #{@change_request.refund_iban}. " \
             "#{StayChangeRequest::REFUND_NOTICE}"
      stay.notes = [stay.notes.presence, line].compact.join("\n")
    end
  end
end
