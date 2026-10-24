# frozen_string_literal: true

module Agenda
  # L'agenda EN RUBANS de la nouvelle interface (redesign, Michael 2026-10-24) :
  # le mois en semaines, chaque séjour en UNE bande qui court de l'après-midi
  # de son arrivée au matin de son départ. Deux séjours qui se suivent
  # partagent donc la même journée, comme dans la réalité du lieu.
  #
  # Rien n'est rechargé ici : on relit les hash `@grouped_*` que
  # `PagesController#load_occupation` a déjà remplis pour l'ancien calendrier,
  # jour par jour, à travers `Calendar::DayStayBlocks` (la même agrégation par
  # séjour que les cellules de l'ancienne grille). Cette classe ne fait que
  # recoudre les jours d'un même séjour en intervalles, les couper par semaine
  # et les ranger sur des lignes.
  #
  # L'unité est la DEMI-JOURNÉE : le jour d'indice i couvre les demis 2i
  # (matin) et 2i+1 (après-midi). Une nuit d dure de l'après-midi de d au matin
  # de d+1 ; une occupation de jour (salle, activité) couvre le jour entier.
  class Month
    # Une bande, telle que la grille la dessine dans UNE semaine.
    # `start` et `span` sont en demi-journées depuis le lundi (0..13).
    Ribbon = Struct.new(:key, :kind, :status, :title, :detail, :icon, :start, :span,
                        :lane, :cont_left, :cont_right, :stay, :record, keyword_init: true)

    Week = Struct.new(:days, :ribbons, :lanes, keyword_init: true)

    # Ce qu'on accumule pour un séjour (ou une occupation sans séjour) avant de
    # le découper en bandes.
    Item = Struct.new(:key, :kind, :status, :title, :resources, :halves, :stay, :record, :icon,
                      keyword_init: true)

    KINDS = %i[lodging room activity meal].freeze
    KIND_ORDER = { lodging: 0, room: 1, activity: 2, meal: 3 }.freeze

    STATUS = {
      "confirmed" => :ok,
      "pre_confirmed" => :pre
    }.freeze

    STATUS_LABELS = { ok: "Confirmé", pre: "Pré-confirmé", wait: "En attente" }.freeze

    attr_reader :month, :first_day, :last_day

    # `sources` : les hash `grouped_*` du contrôleur (mêmes clés que
    # `Calendar::DayStayBlocks`), plus `grouped_coworking_reservations`.
    def initialize(month:, sources:, events:, meals:)
      @month = month.to_date.beginning_of_month
      @first_day = @month.beginning_of_week
      @last_day = @month.end_of_month.end_of_week
      @sources = sources
      @coworking = sources[:grouped_coworking_reservations] || {}
      @events = Array(events)
      @meals = Array(meals)
    end

    def days = (@first_day..@last_day).to_a

    def weeks
      @weeks ||= days.each_slice(7).each_with_index.map do |week_days, index|
        ribbons = items.flat_map { |item| ribbons_for(item, index) }
        lanes = pack(ribbons)
        Week.new(days: week_days, ribbons: ribbons, lanes: lanes)
      end
    end

    # Combien de choses se passent ce jour-là (les points de la bande des
    # jours, sur téléphone) : séjours, occupations, événements, repas seuls.
    def count_on(date)
      index = (date - @first_day).to_i
      items.count { |item| item.halves.include?(2 * index) || item.halves.include?((2 * index) + 1) }
    end

    private

    def items
      @items ||= begin
        by_key = {}
        # La veille du premier lundi aussi : une nuit qui la traverse fait
        # commencer la bande dès le matin du lundi, pas l'après-midi.
        ((@first_day - 1)..@last_day).each do |date|
          index = (date - @first_day).to_i
          blocks = Calendar::DayStayBlocks.new(date, **block_sources)
          blocks.stay_blocks.each { |block| add_stay_block(by_key, block, index) }
          blocks.no_stay_booking_groups.each { |group| add_orphan_booking(by_key, group, index) }
          blocks.no_stay_space_groups.each { |group| add_orphan_space(by_key, group, index) }
          blocks.no_stay_camping.each { |camping| add_orphan_global(by_key, camping, "Tentes", :tent, index) }
          blocks.no_stay_van.each { |van| add_orphan_global(by_key, van, "Van", :bed, index) }
          add_coworking(by_key, date, index)
        end
        @events.each { |event| add_event(by_key, event) }
        @meals.each { |meal| add_meal(by_key, meal) }
        by_key.values.each { |item| item.kind ||= :lodging }
        by_key.values.reject { |item| item.halves.empty? }
      end
    end

    def block_sources
      @sources.slice(:grouped_reservations, :grouped_space_reservations, :grouped_camping_bookings,
                     :grouped_van_bookings, :grouped_hamac_bookings, :grouped_activity_only_bookings,
                     :grouped_bare_stays)
    end

    def add_stay_block(by_key, block, index)
      stay = block.stay
      item = (by_key["stay-#{stay.id}"] ||= Item.new(key: "stay-#{stay.id}", stay: stay, record: stay,
                                                     status: status_for(stay.status), resources: [],
                                                     halves: Set.new))
      bare_night = block.bare && stay.departure_date.to_date > stay.arrival_date.to_date
      if block.overnight? || bare_night
        add_halves(item, (2 * index) + 1, (2 * index) + 3)
      else
        add_halves(item, 2 * index, (2 * index) + 2)
      end
      item.kind = merge_kind(item.kind, kind_for(block))
      item.icon ||= :bed if block.booking_groups.any?
      item.icon ||= :tent if block.camping_bookings.any? || block.hamac_bookings.any?
      item.resources |= resources_for(block)
    end

    def kind_for(block)
      return :lodging if block.overnight?
      return :room if block.space_groups.any? || block.terrace_bookings.any?
      return :activity if block.activity_bookings.any?
      return :meal if block.bare && block.stay.meal_orders.any?

      :lodging
    end

    # Un séjour qui dort sur place ET loue une salle reste un hébergement :
    # la sorte la plus « lourde » l'emporte.
    def merge_kind(current, other)
      return other if current.nil?

      KIND_ORDER.fetch(other) < KIND_ORDER.fetch(current) ? other : current
    end

    def resources_for(block)
      names = block.booking_groups.map do |group|
        group.booking.lodging&.name.presence ||
          group.reservations.map { |reservation| reservation.room&.name }.compact.uniq.join(", ")
      end
      names << "Tentes" if block.camping_bookings.any?
      names << "Van" if block.van_bookings.any?
      names << "Hamacs" if block.hamac_bookings.any?
      names += block.space_groups.flat_map { |group| group.space_reservations.map { |sr| sr.space&.name } }
      names << "Terrasse" if block.terrace_bookings.any?
      names += block.activity_bookings.map { |booking| booking.experience_availability&.experience&.name }
      names.compact_blank.uniq
    end

    def add_orphan_booking(by_key, group, index)
      booking = group.booking.object
      key = "booking-#{booking.id}"
      item = (by_key[key] ||= Item.new(key: key, kind: :lodging, record: booking, icon: :bed,
                                       status: status_for(booking.status), resources: [], halves: Set.new,
                                       title: booking.group_name.presence || booking.name))
      add_halves(item, (2 * index) + 1, (2 * index) + 3)
      item.resources |= [booking.lodging&.name.presence ||
                         group.reservations.map { |reservation| reservation.room&.name }.compact.uniq.join(", ")]
    end

    def add_orphan_space(by_key, group, index)
      space_booking = group.space_booking.object
      key = "space-#{space_booking.id}"
      item = (by_key[key] ||= Item.new(key: key, kind: :room, record: space_booking,
                                       status: status_for(space_booking.status), resources: [], halves: Set.new,
                                       title: space_booking.group_name.presence || space_booking.name))
      add_halves(item, 2 * index, (2 * index) + 2)
      item.resources |= group.space_reservations.map { |sr| sr.space&.name }.compact
    end

    def add_orphan_global(by_key, record, label, icon, index)
      key = "#{record.class.name.underscore}-#{record.id}"
      item = (by_key[key] ||= Item.new(key: key, kind: :lodging, record: nil, icon: icon,
                                       status: status_for(record.try(:status)), resources: [label], halves: Set.new,
                                       title: record.try(:name).presence || label))
      add_halves(item, (2 * index) + 1, (2 * index) + 3)
    end

    # Le coworking reste un bloc par jour (« Coworking 2/3 ») : il ne vit pas
    # dans les séjours, et deux jours de suite ne sont pas les mêmes personnes.
    def add_coworking(by_key, date, index)
      return if index.negative?

      reservations = Array(@coworking[date])
      return if reservations.empty?

      key = "coworking-#{date}"
      item = Item.new(key: key, kind: :room, status: :ok, title: "Coworking #{reservations.size}/3",
                      resources: reservations.map { |reservation| reservation.customer&.name }.compact.uniq,
                      halves: Set.new, record: nil)
      add_halves(item, 2 * index, (2 * index) + 2)
      by_key[key] = item
    end

    # Un événement du lieu : ses jours entiers, l'heure dans le détail. Une
    # demi-journée suffirait au calcul, mais une soirée réduite à un demi-jour
    # n'est plus lisible.
    def add_event(by_key, event)
      record = event.respond_to?(:object) ? event.object : event
      return if record.starts_at.nil?

      from = record.starts_at
      to = [record.ends_at.presence || from, from].max
      key = "event-#{record.id}"
      item = Item.new(key: key, kind: :activity, status: :event, title: record.name, record: record,
                      resources: [[from.strftime("%H:%M"), record.location.presence].compact.join(" · ")], halves: Set.new)
      add_halves(item, 2 * (from.to_date - @first_day).to_i, (2 * (to.to_date - @first_day).to_i) + 2)
      by_key[key] = item
    end

    # Un repas SANS séjour (traiteur, buffet pour un voisin) : son jour. Les
    # repas d'un séjour vivent dans sa bande.
    def add_meal(by_key, meal)
      return if meal.date.nil?

      index = (meal.date - @first_day).to_i
      key = "meal-#{meal.id}"
      item = Item.new(key: key, kind: :meal, status: :meal, title: meal.client_label, record: meal,
                      resources: [[meal.moment_label&.downcase, meal.people].compact.join(", ")], halves: Set.new)
      add_halves(item, 2 * index, (2 * index) + 2)
      by_key[key] = item
    end

    def add_halves(item, from, to)
      (from...to).each { |half| item.halves << half }
    end

    def status_for(status)
      STATUS.fetch(status.to_s, :wait)
    end

    # Les bandes d'un élément dans la semaine `week` : une par suite continue
    # de demi-journées, coupée aux bords de la semaine.
    def ribbons_for(item, week)
      low = 14 * week
      high = low + 14
      title = item.title || label_for(item.stay)
      runs(item.halves.to_a.sort).filter_map do |from, to|
        start = [from, low].max
        finish = [to, high].min
        next if finish <= start

        Ribbon.new(key: item.key, kind: item.kind, status: item.status, icon: item.icon,
                   title: title, detail: (item.resources - [title]).join(" + ").presence,
                   start: start - low, span: finish - start, cont_left: from < low, cont_right: to > high,
                   stay: item.stay, record: item.record)
      end
    end

    def label_for(stay)
      return nil if stay.nil?

      stay.decorate.display_name.presence || "Séjour ##{stay.id}"
    end

    def runs(halves)
      halves.slice_when { |a, b| b != a + 1 }.map { |run| [run.first, run.last + 1] }
    end

    # Rangement sur des lignes : les hébergements d'abord (en haut, ce que
    # l'Accueil lit en premier), puis le reste ; dans chaque groupe par jour
    # de début, la plus longue d'abord, chaque bande sur la première ligne
    # libre. Un départ du matin et une arrivée de l'après-midi tiennent sur
    # la même ligne.
    def pack(ribbons)
      lanes = []
      ribbons.sort_by { |r| [r.kind == :lodging ? 0 : 1, r.start, -r.span, r.title.to_s] }.each do |ribbon|
        finish = ribbon.start + ribbon.span
        lane = lanes.index { |taken| taken.none? { |from, to| from < finish && ribbon.start < to } } || lanes.size
        (lanes[lane] ||= []) << [ribbon.start, finish]
        ribbon.lane = lane
      end
      [lanes.size, 1].max
    end
  end
end
