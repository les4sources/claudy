# frozen_string_literal: true

module Agenda
  # Une journée de l'agenda en rubans (redesign, Michael 2026-10-24) : le
  # panneau à droite de la grille et chaque section de la liste du téléphone.
  #
  # Même lecture que l'écran « Aujourd'hui », pour n'importe quel jour du mois
  # affiché : les séjours viennent de `Calendar::TodayStayCards` (départs du
  # jour compris), les lignes de `Today::Board`. Les hash `grouped_*` sont ceux
  # que le contrôleur a déjà chargés pour la grille : aucune requête de plus
  # pour les séjours. AUCUN MONTANT, comme « Aujourd'hui ».
  class Day
    SpaceRow = Struct.new(:space, :title, :when, :stay, keyword_init: true)

    attr_reader :date

    delegate :entries, :arrivals, :departures, :meals_today, :dinner_covers, :dinner_covers_to_validate,
             :status_pill, to: :board

    def initialize(date:, sources:, events:, user:, full_access:)
      @date = date
      @sources = sources
      @events = events
      @user = user
      @full_access = full_access
    end

    def board
      @board ||= Today::Board.new(date: @date, user: @user, cards: cards, events: @events, full_access: @full_access)
    end

    def cards
      @cards ||= Calendar::TodayStayCards.new(
        date: @date,
        **@sources.slice(:grouped_reservations, :grouped_space_reservations, :grouped_camping_bookings,
                         :grouped_van_bookings, :grouped_hamac_bookings, :grouped_bare_stays,
                         :grouped_activity_only_bookings)
      )
    end

    # Les salles occupées ce jour-là, séjour ou pas.
    def spaces
      @spaces ||= Array(@sources[:grouped_space_reservations]&.[](@date)).map do |reservation|
        booking = reservation.space_booking
        stay = booking.stay
        title = stay ? (stay.decorate.display_name.presence || "Séjour ##{stay.id}") : (booking.group_name.presence || booking.name)
        duration = SpaceBookingDecorator.new(booking).duration if reservation.duration.present?
        SpaceRow.new(space: reservation.space&.name, title: title, when: duration, stay: stay)
      end.uniq { |row| [row.space, row.title] }.sort_by { |row| row.space.to_s }
    end

    def lunch_covers
      meals_today.select { |meal| meal.moment == "midi" && !meal.refused? }.sum(&:people)
    end

    # Les chambres où personne ne dort cette nuit-là (demande en attente
    # comprise : « libre » veut dire sans personne). Seulement celles des
    # hébergements qu'on loue : la pâture et le parking ont leur propre bande.
    def free_rooms
      @free_rooms ||= begin
        taken = Array(@sources[:grouped_reservations]&.[](@date)).map(&:room_id).to_set
        Room.joins(:lodgings).merge(Lodging.where(available_for_bookings: true)).distinct
            .order(:level, :id).reject { |room| taken.include?(room.id) }
      end
    end

    def all_rooms_free?
      free_rooms.any? && Array(@sources[:grouped_reservations]&.[](@date)).empty?
    end

    def notes
      @notes ||= Note.where(date: @date).order(:created_at).to_a
    end

    # Qui veille cette nuit-là (rôle du jour n° 1, comme la fiche du jour).
    def watchers
      @watchers ||= HumanRole.selected.where(date: @date, role_id: 1).includes(:human).filter_map(&:human)
    end

    def empty?
      entries.empty? && spaces.empty? && meals_today.empty?
    end
  end
end
