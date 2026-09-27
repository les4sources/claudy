# La carte du jour (epic #348, phase 3) : qui occupe quoi à une date donnée.
#
# L'occupation d'un gîte se lit dans les `Reservation` de CHAMBRES — une ligne
# par nuit et par chambre, nuits [arrivée, départ) — jamais dans
# `Booking.lodging_id` + dates, qui ne pose ni l'occupation calendrier ni le
# veto. Celle d'une salle se lit dans les `SpaceReservation` du jour.
#
# Statut retenu : `confirmed` SEULEMENT (décision Michael 2026-09-23). La carte
# du jour dit qui est vraiment là : un séjour pré-confirmé bloque le calendrier
# et le veto, mais il n'occupe pas encore le gîte sur la carte.
#
# Trois états par objet :
#   occupied — quelqu'un dort là cette nuit ;
#   turnover — une arrivée ou un départ ce jour (le ménage et l'accueil
#              comptent autant que la nuit) ;
#   free     — ni l'un ni l'autre.
module Maps
  class DayOccupancy
    STATES = %w[occupied turnover free].freeze
    STATUSES = %w[confirmed].freeze
    STATES_BY_ACTIVITY = %w[turnover occupied free].freeze

    Group = Struct.new(:booking, :arriving, :departing, keyword_init: true) do
      def stay = booking.stay
    end

    SpaceGroup = Struct.new(:space_booking, :reservations, keyword_init: true) do
      def stay = space_booking.stay
    end

    attr_reader :date

    def initialize(date)
      @date = date
    end

    # { feature_id => { state:, label: } } pour tous les objets reliés de la
    # couche des lieux. Un nombre fixe de requêtes, quel que soit le nombre de
    # gîtes, de salles et de tracés.
    #
    # Un tracé qui représente plusieurs lieux (la Chevêche et la Hulotte,
    # superposées — issue #370) prend l'état le plus actif de ses lieux, et son
    # libellé les détaille : « La Chevêche : Arrivée · La Hulotte : Libre ».
    def states
      links = MapFeatureVenue.joins(:map_feature)
                             .merge(MapFeature.where(map_layer: MapLayer.where(kind: "venues")))
                             .pluck(:map_feature_id, :venue_type, :venue_id)
      lodging_ids = links.select { |_, type, _| type == "Lodging" }.map(&:last).uniq
      space_ids = links.select { |_, type, _| type == "Space" }.map(&:last).uniq

      rooms_by_lodging = LodgingRoom.where(lodging_id: lodging_ids).pluck(:lodging_id, :room_id)
                                    .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      nights = room_nights(rooms_by_lodging.values.flatten.uniq)
      spaces = space_counts(space_ids)
      space_rows = space_ids.empty? ? [] : Space.unscoped.where(id: space_ids).pluck(:id, :name, :capacity)
      capacities = space_rows.to_h { |id, _, capacity| [id, capacity] }
      names = {
        "Lodging" => lodging_ids.empty? ? {} : Lodging.unscoped.where(id: lodging_ids).pluck(:id, :name).to_h,
        "Space" => space_rows.to_h { |id, name, _| [id, name] }
      }

      # Les gîtes puis les salles, chacun par nom — l'ordre de la fiche.
      links.group_by(&:first).transform_values do |feature_links|
        venue_states = feature_links.sort_by { |_, type, id| [type == "Lodging" ? 0 : 1, names[type][id].to_s] }.map do |_, type, id|
          state =
            if type == "Lodging"
              lodging_state(nights, rooms_by_lodging.fetch(id, []))
            else
              space_state(spaces[id].to_i, capacities[id].to_i)
            end
          [names[type][id], state]
        end
        combine(venue_states)
      end
    end

    # Les séjours présents dans un gîte ce jour-là : ceux qui partent (dernière
    # nuit = la veille) avant ceux qui restent ou arrivent.
    def lodging_groups(lodging)
      bookings = confirmed_bookings_for(lodging.rooms.pluck(:id), [date - 1, date])
      bookings.map do |booking|
        Group.new(booking: booking, arriving: booking.from_date == date, departing: booking.to_date == date)
      end.select { |group| group.departing || booking_sleeps_tonight?(group.booking) }
             .sort_by { |group| [group.departing ? 0 : 1, group.booking.from_date, group.booking.id] }
    end

    # Le prochain séjour à venir dans un gîte libre.
    def next_lodging_booking(lodging)
      booking_id = Reservation.joins(:booking)
                              .where(room_id: lodging.rooms.pluck(:id), date: (date + 1)..)
                              .merge(confirmed_bookings)
                              .order(:date).pick(:booking_id)
      booking_id && Booking.find_by(id: booking_id)
    end

    def space_groups(space)
      SpaceReservation.joins(:space_booking)
                      .where(space_id: space.id, date: date)
                      .merge(confirmed_space_bookings)
                      .includes(space_booking: [:event, { stay: :customer }])
                      .group_by(&:space_booking)
                      .map { |space_booking, reservations| SpaceGroup.new(space_booking: space_booking, reservations: reservations) }
                      .sort_by { |group| group.space_booking.id }
    end

    def next_space_booking(space)
      space_booking_id = SpaceReservation.joins(:space_booking)
                                         .where(space_id: space.id, date: (date + 1)..)
                                         .merge(confirmed_space_bookings)
                                         .order(:date).pick(:space_booking_id)
      space_booking_id && SpaceBooking.find_by(id: space_booking_id)
    end

    private

    # [[room_id, date, from_date, to_date], …] des nuits de la veille et du jour.
    def room_nights(room_ids)
      return [] if room_ids.empty?

      Reservation.joins(:booking)
                 .where(room_id: room_ids, date: [date - 1, date])
                 .merge(confirmed_bookings)
                 .pluck(:room_id, :date, "bookings.from_date", "bookings.to_date")
    end

    def lodging_state(nights, room_ids)
      mine = nights.select { |room_id, *| room_ids.include?(room_id) }
      tonight = mine.select { |_, night, *| night == date }
      arriving = tonight.any? { |_, _, from, _| from == date }
      departing = mine.any? { |_, night, _, to| night == date - 1 && to == date }

      if arriving || departing
        { state: "turnover", label: [("arrivée" if arriving), ("départ" if departing)].compact.join(" et ").capitalize }
      elsif tonight.any?
        { state: "occupied", label: "Occupé" }
      else
        { state: "free", label: "Libre" }
      end
    end

    def space_state(count, capacity)
      return { state: "free", label: "Libre" } if count.zero?

      label = capacity > 1 ? "Occupé (#{count}/#{capacity} groupes)" : "Occupé"
      { state: "occupied", label: label }
    end

    # L'état le plus actif l'emporte : une arrivée sur l'un des lieux se voit
    # sur le bâtiment entier. Un tracé à un seul lieu garde son libellé.
    def combine(venue_states)
      return venue_states.first.last if venue_states.one?

      state = STATES_BY_ACTIVITY.find { |candidate| venue_states.any? { |_, s| s[:state] == candidate } }
      { state: state, label: venue_states.map { |name, s| "#{name} : #{s[:label]}" }.join(" · ") }
    end

    def space_counts(space_ids)
      return {} if space_ids.empty?

      SpaceReservation.joins(:space_booking)
                      .where(space_id: space_ids, date: date)
                      .merge(confirmed_space_bookings)
                      .group(:space_id).count
    end

    def confirmed_bookings_for(room_ids, dates)
      ids = Reservation.joins(:booking)
                       .where(room_id: room_ids, date: dates)
                       .merge(confirmed_bookings)
                       .distinct.pluck(:booking_id)
      Booking.where(id: ids).includes(:lodging, stay: [:customer, :stay_items]).to_a
    end

    def booking_sleeps_tonight?(booking)
      booking.from_date <= date && booking.to_date > date
    end

    # `merge` plutôt qu'un `where(bookings: …)` nu : les séjours supprimés
    # (soft-delete) ne doivent jamais colorer un gîte.
    def confirmed_bookings
      Booking.where(status: STATUSES, deleted_at: nil)
    end

    def confirmed_space_bookings
      SpaceBooking.where(status: STATUSES, deleted_at: nil)
    end
  end
end
