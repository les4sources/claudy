module Stays
  # Action rapide de changement de statut d'un séjour depuis la modale du
  # calendrier (issue #76) : `pending` ↔ `confirmed`, SANS ouvrir le form
  # d'édition complet.
  #
  # ⚠️ Cohérence du VETO de disponibilité : le veto suit le statut des réservables
  # (`available_between?` compte les `Reservation` de `Booking` `confirmed` ;
  # `Space#booked_on?` / capacités globales comptent les réservables `confirmed`).
  # On PROPAGE donc le statut du séjour à TOUS ses bookables — sinon un séjour
  # « confirmé » dont le Booking reste `pending` ne bloquerait pas les chambres.
  #
  # ANTI-SPAM : la propagation coupe l'email client (`skip_customer_notification`
  # sur `Booking`) — même philosophie que `Stays::AdminUpdater`. Un toggle de
  # statut interne ne doit jamais notifier le client.
  #
  # …SAUF la confirmation elle-même (Malau, 2026-08-20). Couper la notification
  # des réservables était juste ; ne rien envoyer du tout ne l'était pas — le
  # client n'apprenait plus jamais que son séjour était confirmé. L'email vit
  # désormais au niveau du SÉJOUR (`Stays::ConfirmationNotifier`), il ne part
  # que sur la BASCULE vers `confirmed` (pas sur un re-`update!` d'un séjour
  # déjà confirmé), et APRÈS le commit : un incident Postmark ne doit pas
  # annuler un changement de statut.
  class QuickStatusUpdater
    ALLOWED = Stay::STATUSES_ADMIN_CREATABLE # %w[pending confirmed]

    attr_reader :stay, :error_message

    def initialize(stay:, status:)
      @stay = stay
      @status = status.to_s
    end

    def run
      unless ALLOWED.include?(@status)
        @error_message = "Statut invalide."
        return false
      end

      was_confirmed = @stay.status == "confirmed"

      Stay.transaction do
        @stay.update!(status: @status)
        propagate_to_bookables!
      end

      notify_customer_of_confirmation! unless was_confirmed
      true
    rescue ActiveRecord::RecordInvalid => e
      @error_message = e.message
      false
    end

    private

    # Bascule vers `confirmed` : c'est le moment — et le seul — où le client
    # doit recevoir sa page de séjour. Le notifier reste muet si le séjour est
    # rattaché à un fourre-tout, sans email, déjà notifié ou déjà terminé.
    def notify_customer_of_confirmation!
      return unless @status == "confirmed"

      Stays::ConfirmationNotifier.call(@stay)
    end

    def propagate_to_bookables!
      @stay.bookables.each do |bookable|
        next unless bookable.respond_to?(:status)

        bookable.skip_customer_notification = true if bookable.respond_to?(:skip_customer_notification=)
        bookable.update!(status: @status)
      end
    end
  end
end
