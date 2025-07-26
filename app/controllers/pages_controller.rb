class PagesController < BaseController
  def calendar
    set_dates
    @events = EventDecorator.decorate_collection(
      Event.all
        .includes(:event_category)
        .between_times(@first, @last)
    )
    # group space reservations by day
    @space_reservations = SpaceReservation.all
      .includes(:space_booking)
      .where.not(space_booking: { status: ["declined", "canceled"] })
      .between_times(@first, @last, field: :date)
    @grouped_space_reservations = @space_reservations.to_a.group_by { |sr| sr.date }
    # group reservations by day
    @reservations = Reservation.all
      .includes(:booking)
      .where.not(booking: { status: ["declined", "canceled"] })
      .between_times(@first, @last, field: :date)
    @grouped_reservations = @reservations.to_a.group_by { |r| r.date }
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
    @humans = Human.all
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

  private

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
