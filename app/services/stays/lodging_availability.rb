module Stays
  # Disponibilité de l'hébergement d'un `Reservations::Draft` pour un séjour
  # donné, en EXCLUANT la propre occupation de ce séjour (sinon un séjour
  # confirmé se bloquerait lui-même à chaque réenregistrement).
  #
  # Extrait tel quel de `Stays::AdminUpdater#lodging_available?` (issue #133)
  # pour que la demande de modification client applique EXACTEMENT la même
  # règle que la validation admin — une seule vérité de dispo, deux appelants.
  class LodgingAvailability
    def initialize(stay:, draft:)
      @stay = stay
      @draft = draft
    end

    def self.call(stay:, draft:) = new(stay: stay, draft: draft).available?

    # true quand il n'y a rien à vérifier (pas d'hébergement demandé).
    def available?
      return true if @draft.lodging.blank?

      if @draft.rooms_mode?
        ids = @draft.lodging.rooms.where(id: @draft.room_ids).pluck(:id)
        # Chambres toutes hors gîte : déjà refusé en validation ; réponse
        # conservatrice si on arrive ici par un autre chemin.
        return false if ids.empty?
      else
        ids = @draft.lodging.rooms.pluck(:id)
        # Gîte sans chambre modélisée : aucune Reservation possible — seule une
        # indisponibilité posée à la main compte (comportement historique).
        return no_unavailability? if ids.empty?
      end

      # Contrat de dates (issue #94) : `[arrival_date, departure_date)` est une
      # fenêtre de séjour ; le jour de départ n'est PAS occupé. Les `Reservation`
      # sont NUITÉES → on borne aux nuits `arrival_date..(departure_date-1)` (borne
      # haute excluant le jour de départ) pour ne pas refuser une rotation dos-à-dos.
      # Le `max` garde un intervalle valide même sur une fenêtre dégénérée (0 nuit).
      last_night = [@draft.departure_date - 1, @draft.arrival_date].max
      scope = Reservation.joins(:booking)
                         .where(date: @draft.arrival_date..last_night,
                                room_id: ids, bookings: { status: "confirmed" })
      own_ids = own_booking_ids
      scope = scope.where.not(bookings: { id: own_ids }) if own_ids.any?
      # Les `Unavailability` gardent leur sémantique de JOURNÉES PLEINES (inclusif
      # du jour de départ) — volontairement différente des nuits ci-dessus.
      scope.none? && no_unavailability?
    end

    private

    def own_booking_ids
      return [] if @stay.nil?

      @stay.stay_items.where(bookable_type: "Booking").pluck(:bookable_id)
    end

    def no_unavailability?
      @draft.lodging.unavailabilities
            .where(date: @draft.arrival_date..@draft.departure_date).none?
    end
  end
end
