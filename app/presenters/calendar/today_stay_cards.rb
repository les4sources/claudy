# frozen_string_literal: true

module Calendar
  # Cartes du bandeau « Aujourd'hui », en haut du calendrier du mois courant.
  #
  # UNE CARTE PAR SÉJOUR. Le bandeau listait jusqu'ici les RÉSERVABLES : une
  # carte par Booking, puis, dans une seconde boucle, une carte par
  # SpaceBooking. Un séjour qui loue un gîte ET des salles — le cas courant —
  # apparaissait donc deux fois, sous deux bandeaux différents, sans que rien ne
  # dise qu'il s'agissait des mêmes gens. Le séjour est le point d'entrée unique
  # depuis l'epic #81 ; le bandeau du veilleur ne pouvait pas rester le dernier
  # écran à raisonner en réservables.
  #
  # L'agrégation elle-même n'est pas réécrite : `DayStayBlocks` la fait déjà
  # pour chaque cellule du calendrier, et c'est la MÊME composition qu'on veut
  # voir en haut de page. Cette classe ne fait que deux choses de plus :
  #
  # · LE DÉPART DU JOUR. Les nuits sont [arrivée, départ) : un séjour qui part
  #   aujourd'hui n'a AUCUNE occupation datée d'aujourd'hui, sa dernière nuit est
  #   celle d'hier. On construit donc aussi les blocs de la veille et on en garde
  #   les séjours dont la date de départ tombe aujourd'hui. C'est la correction
  #   du 2026-07-20, reprise telle quelle — au niveau du séjour cette fois.
  # · LA FUSION DES DEUX JOURS. Un séjour peut partir aujourd'hui (chambres
  #   occupées hier) ET garder une salle jusqu'au soir (occupation datée
  #   d'aujourd'hui). Les deux blocs décrivent le même séjour : on les réunit
  #   pour que la carte montre la composition complète du jour, pas la moitié.
  #
  # Aucune requête ici : on relit les hash `@grouped_*` déjà chargés par
  # `PagesController#calendar`.
  class TodayStayCards
    # Un séjour + son rôle dans la journée (arrivée, départ, journée, en cours).
    #
    # Les accesseurs de contact et d'horaire cherchent D'ABORD sur le séjour,
    # PUIS sur les réservables du jour. Ce n'est pas de la prudence gratuite :
    # `stays.arrival_time` n'est renseigné que sur 4 séjours sur 1496 au
    # 2026-08-28 — l'heure annoncée par le client vit encore sur le Booking
    # (`estimated_arrival`) ou le SpaceBooking (`arrival_time`). Lire le séjour
    # seul aurait fait disparaître de la carte l'heure d'arrivée, qui est
    # exactement ce que le veilleur vient y chercher.
    Card = Struct.new(:block, :state, keyword_init: true) do
      def stay
        block.stay
      end

      def overnight?
        block.overnight?
      end

      # Tous les réservables du séjour présents ce jour-là, hébergement d'abord.
      def bookables
        block.booking_groups.map(&:booking) +
          block.space_groups.map(&:space_booking) +
          block.camping_bookings + block.van_bookings +
          block.terrace_bookings + block.hamac_bookings
      end

      def phone
        # `raw` obligatoire : `BookingDecorator#phone` rend « - » quand la colonne
        # est vide, ce qui passerait le test de présence et masquerait un vrai
        # numéro porté par un autre réservable du séjour.
        first_present(bookables.map { |b| raw(b).try(:phone) })
      end

      def arrival_time
        stay.arrival_time.presence ||
          first_present(bookables.map { |b| raw(b).try(:estimated_arrival) || raw(b).try(:arrival_time) })
      end

      def departure_time
        stay.departure_time.presence ||
          first_present(bookables.map { |b| raw(b).try(:departure_time) })
      end

      # Effectif : occupants du séjour (adultes / enfants des nuitées) et, pour
      # une location de salle qui n'héberge personne, le nombre de personnes
      # annoncé sur la location — sans quoi une journée à 80 personnes
      # s'afficherait sans un seul chiffre.
      def persons
        block.space_groups.map { |group| raw(group.space_booking).persons.to_i }.max.to_i
      end

      # Durées des espaces occupés ce jour-là (« journée + soirée »), dédoublonnées.
      def space_durations
        block.space_groups.map { |group| group.space_booking.duration.presence }.compact.uniq
      end

      private

      def raw(bookable)
        bookable.try(:object) || bookable
      end

      def first_present(values)
        values.compact.map(&:to_s).find(&:present?)
      end
    end

    # Ordre du flux du veilleur : les départs d'abord (ils libèrent les lieux),
    # puis ce qui arrive, puis ce qui est déjà là et ne demande rien.
    STATE_ORDER = { checkout: 0, dayuse: 1, checkin: 2, ongoing: 3 }.freeze

    def initialize(date:, grouped_reservations:, grouped_space_reservations:,
                   grouped_camping_bookings:, grouped_van_bookings:,
                   grouped_hamac_bookings: nil)
      @date = date.to_date
      sources = {
        grouped_reservations: grouped_reservations,
        grouped_space_reservations: grouped_space_reservations,
        grouped_camping_bookings: grouped_camping_bookings,
        grouped_van_bookings: grouped_van_bookings,
        grouped_hamac_bookings: grouped_hamac_bookings
      }
      @today     = DayStayBlocks.new(@date, **sources)
      @yesterday = DayStayBlocks.new(@date - 1, **sources)
    end

    # Cartes séjour du jour, triées selon `STATE_ORDER`.
    def cards
      by_stay = {}

      @today.stay_blocks.each { |block| by_stay[block.stay.id] = block }

      departing_yesterday_blocks.each do |block|
        existing = by_stay[block.stay.id]
        by_stay[block.stay.id] = existing ? merge(existing, block) : block
      end

      by_stay
        .values
        .map { |block| Card.new(block: block, state: state_for(block.stay)) }
        .sort_by { |card| [STATE_ORDER.fetch(card.state, 9), card.stay.arrival_date.to_s, card.stay.id.to_i] }
    end

    # Hébergements SANS séjour rattaché (bookings legacy / OTA) : ils gardent
    # leur carte et leur popover historiques — le bandeau ne peut pas les perdre
    # sous prétexte qu'ils n'ont pas de séjour.
    def orphan_booking_groups
      groups = @today.no_stay_booking_groups +
               @yesterday.no_stay_booking_groups.select { |group| group.booking.to_date == @date }
      groups.uniq { |group| group.booking.id }
    end

    # Locations d'espaces sans séjour rattaché — même raison.
    def orphan_space_groups
      @today.no_stay_space_groups
    end

    def any?
      cards.any? || orphan_booking_groups.any? || orphan_space_groups.any?
    end

    # Rôle du jour dans la vie du séjour. `:dayuse` — arrivée et départ le même
    # jour — est le cas d'une location de salle à la journée : ce n'est ni une
    # arrivée ni un départ, c'est les deux, et le veilleur doit le lire ainsi.
    def state_for(stay)
      from = stay.arrival_date
      to   = stay.departure_date
      return :ongoing if from.blank? || to.blank?
      return :dayuse  if from == @date && to == @date
      return :checkin if from == @date
      return :checkout if to == @date

      :ongoing
    end

    private

    def departing_yesterday_blocks
      @yesterday.stay_blocks.select { |block| block.stay.departure_date == @date }
    end

    # Réunion de deux blocs du MÊME séjour (hier et aujourd'hui). Dédoublonnage
    # par identifiant de réservable : une chambre occupée les deux jours ne doit
    # poser qu'un badge.
    def merge(into, other)
      DayStayBlocks::StayBlock.new(
        stay: into.stay,
        booking_groups: (into.booking_groups + other.booking_groups).uniq { |g| g.booking.id },
        space_groups: (into.space_groups + other.space_groups).uniq { |g| g.space_booking.id },
        camping_bookings: (into.camping_bookings + other.camping_bookings).uniq(&:id),
        van_bookings: (into.van_bookings + other.van_bookings).uniq(&:id),
        terrace_bookings: (into.terrace_bookings + other.terrace_bookings).uniq(&:id),
        hamac_bookings: (into.hamac_bookings + other.hamac_bookings).uniq(&:id)
      )
    end
  end
end
