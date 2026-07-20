# frozen_string_literal: true

module Calendar
  # Agrège, pour UNE date, toutes les occupations calendrier d'un même séjour
  # (chambres, gîte entier, espaces, camping, van) en UN SEUL bloc par séjour.
  # C'est de la PURE AGRÉGATION D'AFFICHAGE : aucune logique de dispo / de veto,
  # aucune requête modifiée — on recompose seulement ce que le contrôleur a déjà
  # chargé dans les hash `@grouped_*` (epic #66) pour le rendu du calendrier.
  #
  # Les occupations SANS séjour rattaché (bookings legacy, OTA, space bookings
  # orphelins) sont renvoyées À PART et gardent leur rendu bloc-par-bloc
  # historique, popovers compris — voir `_day_bookings` / `_bookings`.
  class DayStayBlocks
    # Un bloc unifié : un séjour et ses composants présents ce jour-là.
    StayBlock = Struct.new(
      :stay, :booking_groups, :space_groups, :camping_bookings, :van_bookings,
      keyword_init: true
    ) do
      # Le bookable « nommé » (Booking ou SpaceBooking, tous deux décorés et
      # porteurs de `group_or_name`) qui donne le titre du bloc. Priorité à
      # l'hébergement, puis aux espaces.
      def named_bookable
        booking_groups.first&.booking || space_groups.first&.space_booking
      end

      # Repli quand le séjour n'a que du camping / van (pas de bookable nommé).
      def fallback_bookable
        camping_bookings.first || van_bookings.first
      end
    end

    # Sous-groupe hébergement : un Booking décoré + ses Reservation (chambres).
    BookingGroup = Struct.new(:booking, :reservations, keyword_init: true)
    # Sous-groupe espace : un SpaceBooking décoré + ses SpaceReservation.
    SpaceGroup = Struct.new(:space_booking, :space_reservations, keyword_init: true)

    def initialize(date, grouped_reservations:, grouped_space_reservations:,
                   grouped_camping_bookings:, grouped_van_bookings:)
      @booking_groups = build_booking_groups(grouped_reservations && grouped_reservations[date])
      @space_groups   = build_space_groups(grouped_space_reservations && grouped_space_reservations[date])
      @camping        = Array(grouped_camping_bookings && grouped_camping_bookings[date])
      @van            = Array(grouped_van_bookings && grouped_van_bookings[date])
    end

    # Blocs unifiés (un par séjour), triés par id de séjour puis date d'arrivée
    # — même ordre stable qu'avant, pour ne pas faire sautiller le calendrier.
    def stay_blocks
      by_stay = {}

      @booking_groups.each do |group|
        stay = group.booking.stay
        next if stay.nil?
        (by_stay[stay] ||= new_block(stay)).booking_groups << group
      end

      @space_groups.each do |group|
        stay = group.space_booking.stay
        next if stay.nil?
        (by_stay[stay] ||= new_block(stay)).space_groups << group
      end

      @camping.each do |camping|
        next if camping.stay.nil?
        (by_stay[camping.stay] ||= new_block(camping.stay)).camping_bookings << camping
      end

      @van.each do |van|
        next if van.stay.nil?
        (by_stay[van.stay] ||= new_block(van.stay)).van_bookings << van
      end

      by_stay.values.sort_by { |block| [block.stay.id.to_i, block.stay.arrival_date.to_s] }
    end

    # Hébergements SANS séjour : [BookingGroup, ...] (rendu bloc-par-bloc legacy).
    def no_stay_booking_groups
      @booking_groups.select { |group| group.booking.stay.nil? }
    end

    # Camping / van SANS séjour : gardent leur bloc informatif « Camping » / « Van ».
    def no_stay_camping
      @camping.select { |camping| camping.stay.nil? }
    end

    def no_stay_van
      @van.select { |van| van.stay.nil? }
    end

    private

    def new_block(stay)
      StayBlock.new(stay: stay, booking_groups: [], space_groups: [],
                    camping_bookings: [], van_bookings: [])
    end

    # Réplique le regroupement historique des vues : trie par heure, regroupe par
    # booking, décore, retrie par séjour — mais renvoie des structs typées.
    def build_booking_groups(reservations)
      return [] if reservations.blank?

      reservations
        .sort_by(&:start_time)
        .group_by { |reservation| reservation.booking.id }
        .map do |_booking_id, grouped|
          BookingGroup.new(
            booking: BookingDecorator.new(grouped.first.booking),
            reservations: grouped
          )
        end
        .sort_by { |group| [group.booking.stay&.id.to_i, group.reservations.first.start_time] }
    end

    def build_space_groups(space_reservations)
      return [] if space_reservations.blank?

      space_reservations
        .sort_by(&:start_time)
        .group_by { |space_reservation| space_reservation.space_booking.id }
        .map do |_space_booking_id, grouped|
          SpaceGroup.new(
            space_booking: SpaceBookingDecorator.new(grouped.first.space_booking),
            space_reservations: grouped
          )
        end
        .sort_by { |group| [group.space_booking.stay&.id.to_i, group.space_reservations.first.start_time] }
    end
  end
end
