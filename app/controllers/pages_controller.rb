class PagesController < BaseController
  access_section :calendar, only: %i[calendar today day month_details other_bookings other_space_bookings]
  access_section :everyone, only: :dashboard
  # Les dix dernières notifications suffisent à la colonne du tableau de bord ;
  # au-delà, « Tout voir ».
  DASHBOARD_NOTIFICATIONS = 10
  # Les prochains rôles du jour d'un membre : de quoi voir les semaines qui
  # viennent, pas tout le planning.
  DASHBOARD_ROLES = 6

  def calendar
    set_dates
    @calendar_view = params[:view] == "organisation" ? :organisation : :bookings
    # Cycles réservés à la vue Organisation (demande Michael 2026-07-20) : en
    # mode Accueil, les bandeaux de cycles n'apportent rien à la gestion des
    # séjours et chargent visuellement le calendrier.
    @cycles = @calendar_view == :organisation ? Cycle.overlapping(@first.to_date, @last.to_date) : Cycle.none

    if @calendar_view == :organisation
      @gatherings = GatheringDecorator.decorate_collection(
        Gathering.includes(:gathering_category).between_times(@first, @last)
      )
      @gathering_categories = GatheringCategory.ordered
    else
      load_occupation
    end
  end

  # « Aujourd'hui » (redesign, Michael 2026-10-24) : la journée du domaine en
  # une page — qui arrive, qui part, ce que la cuisine prépare, ce qui attend une
  # réponse. L'occupation est chargée sur HIER et aujourd'hui : un séjour qui
  # part ce matin a passé sa dernière nuit hier (`Calendar::TodayStayCards`).
  def today
    @date = Date.current
    @first = (@date - 1).beginning_of_day
    @last = @date.end_of_day
    load_occupation
    cards = Calendar::TodayStayCards.new(
      date: @date,
      grouped_reservations: @grouped_reservations,
      grouped_space_reservations: @grouped_space_reservations,
      grouped_camping_bookings: @grouped_camping_bookings,
      grouped_van_bookings: @grouped_van_bookings,
      grouped_hamac_bookings: @grouped_hamac_bookings,
      grouped_bare_stays: @grouped_bare_stays
    )
    @board = Today::Board.new(date: @date, user: current_user, cards: cards, events: @events,
                              full_access: section_readable?(:full))
  end

  # Fil d'activité récente — page dédiée (2026-07-20, sortie du bas du
  # calendrier). NB : cette action avait été perdue dans une collision de
  # checkout le soir même (page rendue implicitement avec @activities nil).
  def recent_activity
    @activities = PublicActivity::Activity.where("created_at > ?", 14.days.ago).order(created_at: :desc)
  end

  # Fiche du JOUR (occupation des chambres et des espaces, assignation des
  # rôles). Vue d'OCCUPATION, donc `Stay::BLOCKING_STATUSES` (Michael
  # 2026-09-08) : un séjour pré-confirmé tient ses dates, la personne qui
  # prépare l'accueil doit le voir arriver.
  def day
    @date = Date.parse(params[:date])
    @rooms = RoomDecorator.decorate_collection(Room.all.order(level: :asc, id: :asc))
    @room_reservations = ReservationDecorator.decorate_collection(
      Reservation
        .includes(:booking)
        .where(date: @date, booking: { status: Stay::BLOCKING_STATUSES })
    )
    @spaces = SpaceDecorator.decorate_collection(Space.all.order(id: :asc))
    @space_reservations = SpaceReservationDecorator.decorate_collection(
      SpaceReservation
        .includes(:space_booking)
        .where(date: @date, space_booking: { status: Stay::BLOCKING_STATUSES })
    )
    @roles = Role.all
    # Écran d'assignation des rôles (veilleur, nourrissage…) : on n'y liste que
    # les membres dont la gestion des rôles est activée.
    @humans = Human.roles_enabled
    @human_roles = HumanRole.where(date: @date)
    @lodgings = LodgingDecorator.decorate_collection(Lodging.all)
    render layout: !turbo_frame_request?
  end

  # Tableau de bord d'UN MEMBRE (issue #323). Réunion Pôle Accueil × Cuisine du
  # 2026-09-11 : « je ne me souviens jamais d'avoir eu cette demande » — il
  # manquait un endroit où une personne voit ce qui la concerne, elle, sans
  # filtrer la page Cuisine.
  #
  # Les comptes Claudy sont PARTAGÉS (décision Michael) : la page porte donc un
  # sélecteur de membre, et `human_id` désigne qui on regarde. Sans paramètre on
  # ouvre sur le membre du compte connecté — et quand il n'y en a pas, sur le
  # sélecteur seul. C'est ce dernier cas qui plantait ici (`current_user.human.tasks`
  # sur `nil`).
  #
  # Premier jet limité à la CUISINE : les activités attendent les epics #244 et
  # #25. Un compte cloisonné sur ses activités (`restricted_to_experiences`)
  # n'atteint jamais cette action — `BaseController#restrict_experience_carriers`
  # le renvoie sur son planning, `pages` n'étant pas dans l'allowlist.
  # Les notifications du COMPTE CONNECTÉ (Michael 2026-09-20) : elles ont quitté
  # la cloche de la barre pour la colonne de droite. Elles ne suivent pas le
  # sélecteur de membre — on regarde peut-être la journée de quelqu'un d'autre,
  # mais les notifications restent celles de la personne connectée. Chargées
  # AVANT la sortie anticipée : un compte sans membre les voit quand même.
  def dashboard
    @projects_view = true
    @notifications = current_user.notifications.newest_first.limit(DASHBOARD_NOTIFICATIONS)
    @notifications_unread_count = current_user.notifications.unread.count
    @humans = Human.all
    @human  = dashboard_human
    return if @human.nil?

    @kitchen_pending     = kitchen_scope.pending_validation.upcoming.chronological.to_a
    @kitchen_upcoming    = kitchen_upcoming_orders
    @kitchen_unconfirmed = kitchen_unconfirmed_orders
    @tasks = TaskDecorator.decorate_collection(@human.tasks)
    load_collective_work if section_readable?(:full)
  end

  # « Qui d'autre est sur place pendant cette réservation ? » — vue d'OCCUPATION
  # elle aussi : `Stay::BLOCKING_STATUSES` (Michael 2026-09-08).
  def other_bookings
    @reservations = Reservation.all
      .includes(:booking)
      .where(booking: { status: Stay::BLOCKING_STATUSES })
      .where.not(booking_id: params[:booking_id])
      .between_times(Date.parse(params[:from_date]), Date.parse(params[:to_date]) - 1.day, field: :date)
      .order(date: :asc)
    # group bookings by day
    @grouped_reservations = @reservations.to_a.group_by { |r| r.date }
    render layout: false
  end

  def other_space_bookings
    @space_reservations = SpaceReservation.all
      .includes(:space_booking)
      .where.not(space_booking: { status: "declined" })
      .where.not(space_booking_id: params[:space_booking_id])
      .between_times(Date.parse(params[:from_date]), Date.parse(params[:to_date]), field: :date)
      .order(date: :asc)
    # group bookings by day
    @grouped_space_reservations = @space_reservations.to_a.group_by { |r| r.date }
    render layout: false
  end

  def month_details
    # Déterminer la période à partir de la date en paramètre
    @date = Date.parse(params[:date])
    @period_start = @date.beginning_of_month
    @period_end = @date.end_of_month
    
    # Récupérer tous les humains actifs avec leur nombre de veilles dans la période
    watchman_counts = HumanRole
      .where(role_id: 1, status: :selected, date: @period_start..@period_end)
      .joins(:human)
      .group('humans.id')
      .count

    # Créer la liste avec tous les humains actifs (même ceux avec 0 veilles)
    # Le default_scope de Human filtre déjà par status: 'active' ; on restreint
    # en plus aux membres dont la gestion des rôles est activée.
    all_active_humans = Human.roles_enabled.pluck(:id, :name).to_h
    @watchman_stats = all_active_humans.map do |human_id, human_name|
      {
        human: Human.find(human_id),
        count: watchman_counts[human_id] || 0
      }
    end.sort_by { |stat| -stat[:count] }
    
    render layout: false
  end

  private

  # --- Tableau de bord d'un membre (issue #323) -----------------------------

  # Le membre affiché. `human_id` d'abord — le sélecteur permet de regarder la
  # vue de n'importe qui depuis n'importe quel compte partagé — puis le membre du
  # compte connecté. `nil` est un état LÉGITIME (compte non rattaché, ou id
  # inconnu) : la vue montre alors le sélecteur seul, jamais une erreur.
  def dashboard_human
    requested = params[:human_id].presence
    return Human.find_by(id: requested) if requested

    current_user&.human
  end

  # Le travail du membre dans le collectif (Michael 2026-10-18) : ses actions du
  # cycle, ses actions de rassemblement, ses prochains rôles du jour. Ces écrans
  # sont réservés aux Sourciers ; le tableau de bord ne les montre donc qu'à eux.
  def load_collective_work
    @cycle = Cycle.reference_for
    if @cycle
      @cycle_actions = @human.cycle_actions.for_cycle(@cycle).live.active.ordered.to_a
      # Ce que d'autres membres ont confié à celui-ci, dans le même cycle.
      @delegated_actions = CycleAction.for_cycle(@cycle).live.active
                                      .where(delegate_to_human_id: @human.id)
                                      .includes(:human).ordered.to_a
    end
    @gathering_actions = @human.gathering_actions.active.includes(:gathering)
                               .order(created_at: :desc).to_a
    # Les points qu'il porte aux prochains rassemblements, dans l'ordre des dates.
    @carried_agenda_items = @human.carried_agenda_items.pending
                                  .joins(:gathering).merge(Gathering.upcoming)
                                  .includes(:gathering).to_a
    @upcoming_roles = HumanRole.where(human_id: @human.id, date: Date.current..)
                               .includes(:role).order(:date, :role_id)
                               .limit(DASHBOARD_ROLES).to_a
  end

  # Toutes les demandes de cuisine dont CE membre est le responsable. Les séjours
  # et leurs clients sont préchargés : chaque ligne affiche le nom du dossier.
  def kitchen_scope
    MealOrder.where(responsible_human_id: @human.id).includes(stay: :customer)
  end

  # « Mes prochains services » — accepté, non annulé, DATÉ et à partir
  # d'aujourd'hui. Le scope `upcoming` ne convient pas ici : il garde les lignes
  # sans date, qui n'ont pas leur place dans un ordre du jour.
  def kitchen_upcoming_orders
    kitchen_scope.where(validation: "accepted")
                 .where.not(status: "cancelled")
                 .where(date: Date.current..)
                 .chronological
                 .to_a
  end

  # « En attente du client » — ce que le membre a accepté et que le client n'a
  # pas confirmé. `upcoming` (et non une borne stricte) : une demande sans date
  # est justement celle dont on attend une réponse.
  def kitchen_unconfirmed_orders
    kitchen_scope.where(validation: "accepted", status: %w[inquiry requested])
                 .upcoming
                 .chronological
                 .to_a
  end

  # Étale une collection de réservables « capacité globale » (camping / van), qui
  # ne portent QUE des dates [from_date, to_date), en un hash { jour => [records] }
  # borné à la fenêtre visible du calendrier. Une nuit `d` est couverte si
  # `from_date <= d < to_date` (même convention que `GlobalCapacityBookable`).
  def nights_grouped_by_day(records)
    window_start = @first.to_date
    window_end   = @last.to_date
    grouped = {}
    records.each do |record|
      next unless record.from_date && record.to_date
      (record.from_date...record.to_date).each do |night|
        next unless night >= window_start && night <= window_end
        (grouped[night] ||= []) << record
      end
    end
    grouped
  end

  # Jours où dessiner un séjour sans réservable : ses nuits [arrivée, départ),
  # ou son unique jour quand il arrive et repart le même jour.
  def stay_days_grouped_by_day(stays)
    window = @first.to_date..@last.to_date
    grouped = {}
    stays.each do |stay|
      days = stay.departure_date > stay.arrival_date ? (stay.arrival_date...stay.departure_date) : [stay.arrival_date]
      days.each do |day|
        (grouped[day] ||= []) << stay if window.cover?(day)
      end
    end
    grouped
  end

  # L'occupation du domaine sur la fenêtre [@first, @last] : séjours, espaces,
  # camping, van, hamacs, coworking, événements. Partagée par l'agenda et par
  # l'écran « Aujourd'hui » (redesign, 2026-10-24), qui la lit sur hier et
  # aujourd'hui pour retrouver les départs du jour.
  def load_occupation
    @events = EventDecorator.decorate_collection(
      Event.all
        .includes(:event_category)
        .between_times(@first, @last)
    )
    # group space reservations by day
    # Le calendrier bascule sur les SÉJOURS (epic #66, Phase 4) : on précharge
    # `space_booking.stay` (via `stay_item`, has_one through) pour colorer et
    # regrouper les occupations par `stay_id` sans requête N+1. Les
    # `stay_items` et leurs réservables viennent avec : le titre du bloc est
    # `StayDecorator#display_name`, qui les relit sur un séjour rattaché au
    # client FOURRE-TOUT pour retrouver le nom de la réservation d'origine.
    @space_reservations = SpaceReservation.all
      .includes(:space_booking)
      .preload(:space, space_booking: [:event, :space_reservations, { stay: [:customer, { stay_items: :bookable }] }])
      .where.not(space_booking: { status: ["declined", "canceled"] })
      .between_times(@first, @last, field: :date)
    @grouped_space_reservations = @space_reservations.to_a.group_by { |sr| sr.date }
    # group reservations by day (préchargement du séjour porteur, cf. supra)
    @reservations = Reservation.all
      .includes(:booking)
      .preload(:room, booking: [:lodging, :reservations, { stay: [:customer, { stay_items: :bookable }] }])
      .where.not(booking: { status: ["declined", "canceled"] })
      .between_times(@first, @last, field: :date)
    @grouped_reservations = @reservations.to_a.group_by { |r| r.date }
    # Camping / van (epic #66, Phase 3–4) — capacité globale, aucune réservation
    # jour par jour : on étale la fenêtre [from, to) en nuits, groupées par jour,
    # pour un bloc agrégé (« Camping » / « Van ») par nuit occupée, coloré par
    # séjour. Préchargement du séjour (anti-N+1).
    @grouped_camping_bookings = nights_grouped_by_day(
      CampingBooking
        .includes(stay: [:customer, { stay_items: :bookable }])
        .where.not(status: ["declined", "canceled"])
        .where("from_date < ? AND to_date > ?", @last.to_date, @first.to_date)
    )
    # Séjours « activité seule » (Michael, 2026-10-13) : un séjour sans
    # hébergement, espace, camping, van ni hamac (un atelier pizza pour un
    # groupe venu à la journée) n'avait aucun réservable à dessiner et
    # n'apparaissait donc jamais au calendrier. On l'y pose au jour de son
    # activité. Un séjour qui a déjà un réservable garde son bloc habituel :
    # ses activités n'y ajoutent rien.
    @grouped_activity_only_bookings = ExperienceBooking.active.with_visible_stay
      .joins(:experience_availability)
      .where(experience_availabilities: { available_on: @first.to_date..@last.to_date })
      .where.not(stays: { status: "canceled" })
      .where.not(stay_id: StayItem.select(:stay_id))
      .preload(:stay, experience_availability: :experience)
      .to_a
      .group_by { |experience_booking| experience_booking.experience_availability.available_on }
    # Séjours SANS rien de dessinable (Michael, 2026-10-23) : le séjour vide
    # (PR #544, client + dates) et le séjour qui n'a que des repas, du linge
    # ou une Pizza Party. Aucun réservable ni activité active : il n'avait
    # donc aucun bloc. On le pose sur ses propres dates, nuits [arrivée,
    # départ) comme un hébergement, ou sur son seul jour s'il tient en une
    # journée.
    @grouped_bare_stays = stay_days_grouped_by_day(
      Stay
        .where.not(status: Stay::CANCELED_STATUSES)
        .where.not(arrival_date: nil).where.not(departure_date: nil)
        .where("arrival_date <= ? AND departure_date >= ?", @last.to_date, @first.to_date)
        .where.not(id: StayItem.select(:stay_id))
        .where.not(id: ExperienceBooking.active.select(:stay_id))
        .preload(:customer, :meal_orders)
    )
    # Coworking (epic #126, Phase 1) — domaine INDÉPENDANT des séjours : un
    # bloc agrégé par jour (« 💻 Coworking N/3 »), jamais rattaché à un stay
    # et donc jamais sélectionnable par le mode fusion.
    @grouped_coworking_reservations = CoworkingReservation
      .includes(:customer)
      .between(@first.to_date, @last.to_date)
      .to_a
      .group_by(&:date)
    @grouped_van_bookings = nights_grouped_by_day(
      VanBooking
        .includes(stay: [:customer, { stay_items: :bookable }])
        .where.not(status: ["declined", "canceled"])
        .where("from_date < ? AND to_date > ?", @last.to_date, @first.to_date)
    )
    # Hamacs (issue #138) — même étalement par nuit que camping/van : ils
    # comptent dans le bloc du séjour (chip 🛌) et dans la nuitée (💤).
    @grouped_hamac_bookings = nights_grouped_by_day(
      HamacBooking
        .includes(stay: [:customer, { stay_items: :bookable }])
        .where.not(status: ["declined", "canceled"])
        .where("from_date < ? AND to_date > ?", @last.to_date, @first.to_date)
    )
  end

  def set_dates
    # get the date from params if there is one - for display AND to limit our query
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    @first = @date.beginning_of_month.beginning_of_day - 7.days
    @last = @date.end_of_month.end_of_day + 7.days
    # @dates = (@date.beginning_of_month..@date.end_of_month).map(&:to_date)
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "dashboard",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end
end
