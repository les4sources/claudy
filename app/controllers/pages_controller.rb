class PagesController < BaseController
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
      @events = EventDecorator.decorate_collection(
        Event.all
          .includes(:event_category)
          .between_times(@first, @last)
      )
      # group space reservations by day
      # Le calendrier bascule sur les SÉJOURS (epic #66, Phase 4) : on précharge
      # `space_booking.stay` (via `stay_item`, has_one through) pour colorer et
      # regrouper les occupations par `stay_id` sans requête N+1.
      @space_reservations = SpaceReservation.all
        .includes(:space_booking)
        .preload(:space, space_booking: [:event, :space_reservations, { stay: :customer }])
        .where.not(space_booking: { status: ["declined", "canceled"] })
        .between_times(@first, @last, field: :date)
      @grouped_space_reservations = @space_reservations.to_a.group_by { |sr| sr.date }
      # group reservations by day (préchargement du séjour porteur, cf. supra)
      @reservations = Reservation.all
        .includes(:booking)
        .preload(:room, booking: [:lodging, :reservations, { stay: :customer }])
        .where.not(booking: { status: ["declined", "canceled"] })
        .between_times(@first, @last, field: :date)
      @grouped_reservations = @reservations.to_a.group_by { |r| r.date }
      # Camping / van (epic #66, Phase 3–4) — capacité globale, aucune réservation
      # jour par jour : on étale la fenêtre [from, to) en nuits, groupées par jour,
      # pour un bloc agrégé (« Camping » / « Van ») par nuit occupée, coloré par
      # séjour. Préchargement du séjour (anti-N+1).
      @grouped_camping_bookings = nights_grouped_by_day(
        CampingBooking
          .includes(stay: :customer)
          .where.not(status: ["declined", "canceled"])
          .where("from_date < ? AND to_date > ?", @last.to_date, @first.to_date)
      )
      @grouped_van_bookings = nights_grouped_by_day(
        VanBooking
          .includes(stay: :customer)
          .where.not(status: ["declined", "canceled"])
          .where("from_date < ? AND to_date > ?", @last.to_date, @first.to_date)
      )
    end
  end

  # Fil d'activité récente — page dédiée (2026-07-20, sortie du bas du
  # calendrier). NB : cette action avait été perdue dans une collision de
  # checkout le soir même (page rendue implicitement avec @activities nil).
  def recent_activity
    @activities = PublicActivity::Activity.where("created_at > ?", 14.days.ago).order(created_at: :desc)
  end

  # details for a specific day
  def day
    @date = Date.parse(params[:date])
    @rooms = RoomDecorator.decorate_collection(Room.all.order(level: :asc, id: :asc))
    @room_reservations = ReservationDecorator.decorate_collection(
      Reservation
        .includes(:booking)
        .where(date: @date, booking: { status: "confirmed" })
    )
    @spaces = SpaceDecorator.decorate_collection(Space.all.order(id: :asc))
    @space_reservations = SpaceReservationDecorator.decorate_collection(
      SpaceReservation
        .includes(:space_booking)
        .where(date: @date, space_booking: { status: "confirmed" })
    )
    @roles = Role.all
    # Écran d'assignation des rôles (veilleur, nourrissage…) : on n'y liste que
    # les membres dont la gestion des rôles est activée.
    @humans = Human.roles_enabled
    @human_roles = HumanRole.where(date: @date)
    @lodgings = LodgingDecorator.decorate_collection(Lodging.all)
    render layout: !turbo_frame_request?
  end

  def dashboard
    @projects_view = true
  end

  def other_bookings
    @reservations = Reservation.all
      .includes(:booking)
      .where(booking: { status: "confirmed" })
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
