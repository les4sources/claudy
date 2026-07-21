module Coworking
  # Annulation d'une journée de coworking par le client depuis le portail
  # (epic #126, Phase 3).
  #
  # Fenêtre d'annulation : jusqu'à 08:00 (Europe/Brussels) le jour même. Passé
  # ce cap, la journée est due et n'est plus annulable en self-service.
  #
  # L'annulation soft-delete la réservation : le crédit du pack redevient
  # immédiatement disponible (`days_used` ne compte que les réservations
  # vivantes), réutilisable dès le prochain jour libre.
  class CancelDay < ServiceBase
    CUTOFF_HOUR = 8
    ZONE = "Europe/Brussels".freeze

    attr_reader :reservation

    def initialize(reservation:)
      @reservation = reservation
      @report_errors = true
    end

    # Cap d'annulation pour une date donnée : ce jour-là à 08:00, heure de
    # Bruxelles. Exposé en classe pour que la vue affiche/masque le bouton avec
    # exactement la même règle que le service.
    def self.deadline_for(date)
      Time.use_zone(ZONE) do
        Time.zone.local(date.year, date.month, date.day, CUTOFF_HOUR, 0, 0)
      end
    end

    def self.cancellable?(date, now: Time.current)
      now < deadline_for(date)
    end

    def run
      unless self.class.cancellable?(@reservation.date)
        set_error_message("Cette journée n'est plus annulable (le délai de 8h le jour même est dépassé).")
        return false
      end

      catch_error(context: { reservation: @reservation.id }) do
        @reservation.soft_delete!(validate: false)
        true
      end
    end
  end
end
