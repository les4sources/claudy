# frozen_string_literal: true

module Today
  # L'écran « Aujourd'hui » de la nouvelle interface (redesign, Michael
  # 2026-10-24) : la journée du domaine en une page, pour qui ouvre Claudy le
  # matin.
  #
  # Rien n'est recalculé ici : les séjours du jour viennent de
  # `Calendar::TodayStayCards` (la même agrégation que le bandeau du
  # calendrier, départs du jour compris), la cuisine de `MealOrder`, les rôles de
  # `HumanRole`, le cycle de `CycleAction`. Cette classe ne fait que choisir,
  # compter et ordonner.
  #
  # AUCUN MONTANT : la page est lue par tous les rôles qui voient l'agenda, sur
  # des comptes partagés (même règle que le tableau de bord d'un membre).
  class Board
    # Une ligne de la journée : un séjour qui arrive, part ou occupe une salle,
    # ou un événement du lieu. `stay` est nil pour un événement.
    Entry = Struct.new(:time, :kind, :title, :detail, :status, :stay, :people, keyword_init: true)

    STATUS_PILLS = {
      "pending" => [:wait, "En attente"],
      "pre_confirmed" => [:pre, "Pré-confirmé"],
      "confirmed" => [:ok, "Confirmé"]
    }.freeze

    NUMBERS_F = %w[zéro une deux trois quatre cinq six sept huit neuf dix].freeze
    NUMBERS_M = %w[zéro un deux trois quatre cinq six sept huit neuf dix].freeze

    MOMENT_ORDER = { "midi" => 0, "gouter" => 1, "soir" => 2 }.freeze

    attr_reader :date

    def initialize(date:, user:, cards:, events:, full_access:)
      @date = date
      @user = user
      @cards = cards
      @events = Array(events)
      @full_access = full_access
    end

    def full_access? = @full_access

    def first_name
      @user&.linked_human&.name.to_s.split.first
    end

    # ---- La journée en chiffres ------------------------------------------

    def arrivals = @arrivals ||= cards_in(:checkin)
    def departures = @departures ||= cards_in(:checkout)

    def arrivals_people = arrivals.sum { |card| people(card) }

    # Ceux qui dorment sur place ce soir : arrivés aujourd'hui ou déjà là, avec
    # une nuit. Une salle louée à la journée ne compte pas.
    def staying_tonight
      @staying_tonight ||= @cards.cards.select { |card| %i[checkin ongoing].include?(card.state) && card.overnight? }
    end

    def staying_tonight_people = staying_tonight.sum { |card| people(card) }

    def meals_today
      @meals_today ||= MealOrder.where(date: @date).where.not(status: "cancelled")
                                .includes(:responsible_human, stay: :customer)
                                .sort_by { |meal| [MOMENT_ORDER.fetch(meal.moment.to_s, 3), meal.id] }
    end

    def dinner = meals_today.select { |meal| meal.moment == "soir" && !meal.refused? }
    def dinner_covers = dinner.sum(&:people)
    def dinner_covers_to_validate = dinner.select { |meal| meal.board_status == "to_validate" }.sum(&:people)

    # ---- La phrase du jour -----------------------------------------------

    # [texte avant, mot surligné, texte après]. Un seul mot surligné : le chiffre
    # qui demande d'agir. Les couverts du soir quand il y en a, sinon les
    # arrivées.
    def phrase
      hello = first_name.present? ? "Bonjour #{first_name}." : "Bonjour."
      parts = []
      parts << count_words(arrivals.size, "arrivée", "arrivées", NUMBERS_F) if arrivals.any?
      parts << count_words(departures.size, "départ", "départs", NUMBERS_M) if departures.any?

      if dinner_covers.positive?
        head = parts.any? ? "#{hello} #{capitalize_first(parts.join(', '))} et " : "#{hello} Ce soir, "
        tail = parts.any? ? " ce soir." : " à préparer."
        [head, "#{dinner_covers} couverts", "#{tail}#{kitchen_waiting_sentence}"]
      elsif parts.any?
        first, *rest = parts
        after = rest.any? ? ", #{to_sentence(rest)}." : "."
        ["#{hello} ", capitalize_first(first), "#{after}#{kitchen_waiting_sentence}"]
      else
        ["#{hello} ", "Journée calme", " : personne n’arrive ni ne part."]
      end
    end

    # ---- Accueil du jour -------------------------------------------------

    # Départs du matin, arrivées, salles, événements : dans l'ordre de l'horloge.
    # Une heure inconnue se range à son moment habituel (départ 11:00, arrivée
    # 16:00) sans être affichée comme sûre.
    def entries
      @entries ||= begin
        rows = @cards.cards.reject { |card| card.state == :ongoing }.map { |card| stay_entry(card) }
        rows += @events.select { |event| event.starts_at&.to_date == @date }.map { |event| event_entry(event) }
        rows.sort_by { |entry| [entry.time.presence || "99", entry.title.to_s] }
      end
    end

    # ---- Cuisine du jour ---------------------------------------------------

    def meal_rows = meals_today

    # ---- À traiter ----------------------------------------------------------

    # Seulement ce qui demande une réponse de l'équipe. Chaque ligne mène à
    # l'écran où l'on y répond.
    def todos
      return [] unless full_access?

      @todos ||= [pending_stays_todo, change_requests_todo, activities_todo, kitchen_todo].compact
    end

    # ---- Pour toi ------------------------------------------------------------
    # Ce qui concerne la personne connectée, repris du tableau de bord d'un
    # membre (Michael 2026-10-24) : la cuisine qui attend SA réponse, ses
    # notifications non lues, les points qu'elle porte aux prochains
    # rassemblements, ses actions de rassemblement et de projet. Le travail
    # du collectif reste réservé aux Sourciers, comme sur le tableau de bord.

    def human = @user&.linked_human

    # Les demandes que la cuisine (ce membre) n'a pas encore tranchées.
    def my_kitchen_to_answer
      return [] if human.nil?

      @my_kitchen_to_answer ||= MealOrder.where(responsible_human_id: human.id).pending_validation.upcoming
                                         .chronological.includes(stay: :customer).limit(3).to_a
    end

    # Son prochain service accepté, après aujourd'hui (aujourd'hui est déjà dans
    # « Cuisine du jour »).
    def my_next_service
      return nil if human.nil?

      @my_next_service ||= MealOrder.where(responsible_human_id: human.id, validation: "accepted")
                                    .where.not(status: "cancelled").where(date: (@date + 1)..)
                                    .chronological.includes(stay: :customer).first
    end

    def my_unread_notifications
      return [] if @user.nil?

      @my_unread_notifications ||= @user.notifications.unread.newest_first.limit(3).to_a
    end

    def my_unread_count = @user ? (@my_unread_count ||= @user.notifications.unread.count) : 0

    def my_agenda_items
      return [] if human.nil? || !full_access?

      @my_agenda_items ||= human.carried_agenda_items.pending.joins(:gathering).merge(Gathering.upcoming)
                                .includes(:gathering).limit(3).to_a
    end

    def my_gathering_actions_count
      return 0 if human.nil? || !full_access?

      @my_gathering_actions_count ||= human.gathering_actions.active.count
    end

    # Ses actions de projet ouvertes, la plus urgente d'abord (échéance, puis
    # sans échéance). `closed` et `canceled` sont sorties du jeu.
    def my_open_tasks
      return [] if human.nil? || !full_access?

      @my_open_tasks ||= human.tasks.where("tasks.status IS NULL OR tasks.status NOT IN (?)", [Task::STATUS_CLOSED, Task::STATUS_CANCELED])
                              .includes(:project)
                              .order(Arel.sql("due_date IS NULL, due_date"), :created_at).limit(3).to_a
    end

    def for_me_empty?
      my_kitchen_to_answer.empty? && my_next_service.nil? && my_unread_notifications.empty? &&
        my_agenda_items.empty? && my_gathering_actions_count.zero? && my_open_tasks.empty?
    end

    # ---- Rôles du jour -------------------------------------------------------

    def roles_today
      @roles_today ||= HumanRole.selected.where(date: @date).includes(:role, :human)
                                .order(:role_id).to_a
    end

    # Ses prochains rôles du jour, sur deux semaines (demain d'abord).
    def my_upcoming_roles
      return [] if human.nil?

      @my_upcoming_roles ||= HumanRole.selected.where(human_id: human.id, date: (@date + 1)..(@date + 14))
                                      .includes(:role).order(:date, :role_id).limit(3).to_a
    end

    # ---- Mon cycle -----------------------------------------------------------

    def cycle
      @cycle ||= Cycle.reference_for(@date)
    end

    def cycle_actions
      return [] if human.nil? || cycle.nil?

      @cycle_actions ||= human.cycle_actions.for_cycle(cycle).live.active.ordered.limit(5).to_a
    end

    # Ce que d'autres membres lui ont confié dans le même cycle.
    def delegated_actions
      return [] if human.nil? || cycle.nil?

      @delegated_actions ||= CycleAction.for_cycle(cycle).live.active.where(delegate_to_human_id: human.id)
                                        .includes(:human).ordered.limit(3).to_a
    end

    def cycle_week
      return nil if cycle.nil? || !(cycle.start_date..cycle.end_date).cover?(@date)

      [((@date - cycle.start_date).to_i / 7) + 1, (((cycle.end_date - cycle.start_date).to_i) / 7.0).ceil.clamp(1, 52)]
    end

    def status_pill(stay)
      STATUS_PILLS[stay&.status.to_s]
    end

    private

    def cards_in(state)
      @cards.cards.select { |card| card.state == state || (card.state == :dayuse && state == :checkin) }
    end

    def people(card)
      occupants = card.stay.decorate.occupants
      total = occupants[:adults].to_i + occupants[:children].to_i
      total.positive? ? total : [card.persons.to_i, card.block.activity_bookings.sum { |booking| booking.participants.to_i }].max
    end

    def stay_entry(card)
      kind = { checkin: :arrival, checkout: :departure, dayuse: :day }.fetch(card.state, :day)
      time = kind == :departure ? card.departure_time : card.arrival_time
      # Un séjour venu pour une activité seulement (agenda en rubans) : la
      # ligne dit « Activité » et prend l'heure du créneau.
      if activity_only?(card)
        kind = :activity
        time = card.block.activity_bookings.filter_map { |booking| booking.experience_availability&.starts_at.presence }.min || time
      end
      count = people(card)
      detail = [place_label(card), nights_label(card.stay, kind), (count.positive? ? "#{count} pers." : nil)].compact.join(" · ")
      Entry.new(time: normalize_time(time) || default_time(kind), kind: kind,
                title: card.stay.decorate.display_name.presence || "Séjour ##{card.stay.id}",
                detail: detail, status: status_pill(card.stay), stay: card.stay, people: count)
    end

    def event_entry(event)
      # Les événements du calendrier arrivent décorés, et le décorateur de la
      # catégorie rend une pastille HTML : on lit le nom brut.
      record = event.respond_to?(:object) ? event.object : event
      detail = [record.event_category&.read_attribute(:name).presence, record.location.presence].compact.join(" · ")
      Entry.new(time: event.starts_at.strftime("%H:%M"), kind: :event, title: event.name,
                detail: detail, status: nil, stay: nil)
    end

    def place_label(card)
      block = card.block
      names = block.booking_groups.map do |group|
        group.booking.lodging&.name.presence || group.reservations.map { |r| r.room&.name }.compact.uniq.join(", ")
      end
      names += block.space_groups.flat_map { |group| group.space_reservations.map { |sr| sr.space&.name } }
      names << "Espace tentes" if block.camping_bookings.any?
      names << "Camping-cars" if block.van_bookings.any?
      names << "Hamacs" if block.hamac_bookings.any?
      names << "Terrasse" if block.terrace_bookings.any?
      names += block.activity_bookings.map { |booking| booking.experience_availability&.experience&.name }
      names.compact_blank.uniq.join(" + ").presence
    end

    def activity_only?(card)
      block = card.block
      block.activity_bookings.any? && !block.overnight? && block.space_groups.empty? && block.terrace_bookings.empty?
    end

    def nights_label(stay, kind)
      return nil unless kind == :arrival && stay.arrival_date && stay.departure_date

      nights = (stay.departure_date - stay.arrival_date).to_i
      nights.positive? ? "#{nights} nuit#{'s' if nights > 1}" : nil
    end

    def normalize_time(value)
      match = value.to_s.match(/(\d{1,2})\s*[:hH.]\s*(\d{2})?/)
      return nil unless match

      format("%02d:%s", match[1].to_i, match[2] || "00")
    end

    def default_time(kind)
      { departure: "11:00", arrival: "16:00" }[kind]
    end

    def kitchen_waiting_sentence
      waiting = dinner.select { |meal| meal.board_status == "to_validate" }
      return "" if waiting.empty?

      names = waiting.map(&:client_label).uniq
      " La cuisine n’a pas encore répondu pour #{to_sentence(names)}."
    end

    def pending_stays_todo
      scope = Stay.where(status: "pending").where("departure_date IS NULL OR departure_date >= ?", @date)
      count = scope.count
      return nil if count.zero?

      oldest = scope.minimum(:created_at)
      { title: count == 1 ? "1 demande de séjour sans réponse" : "#{count} demandes de séjour sans réponse",
        detail: oldest ? "la plus ancienne depuis le #{I18n.l(oldest.to_date, format: '%-d %B')}" : nil,
        path: [:stays, { status: "pending" }] }
    end

    def change_requests_todo
      count = StayChangeRequest.pending.count
      return nil if count.zero?

      { title: count == 1 ? "1 modification demandée par un client" : "#{count} modifications demandées par des clients",
        detail: "à accepter ou refuser", path: [:stays, {}] }
    end

    def activities_todo
      count = ExperienceBooking.pending.with_visible_stay.count
      return nil if count.zero?

      { title: count == 1 ? "1 activité à valider" : "#{count} activités à valider",
        detail: "par le porteur ou l’accueil", path: [:experience_bookings, {}] }
    end

    def kitchen_todo
      count = MealOrder.pending_validation.upcoming.count
      return nil if count.zero?

      { title: count == 1 ? "1 demande en cuisine attend sa réponse" : "#{count} demandes en cuisine attendent leur réponse",
        detail: "la cuisine dit oui ou non", path: [:kitchen_orders, {}] }
    end

    def count_words(count, singular, plural, numbers)
      word = numbers[count] || count.to_s
      "#{word} #{count == 1 ? singular : plural}"
    end

    def to_sentence(items)
      items.to_sentence(words_connector: ", ", two_words_connector: " et ", last_word_connector: " et ")
    end

    def capitalize_first(text)
      text.to_s.sub(/\A\p{Ll}/, &:upcase)
    end
  end
end
