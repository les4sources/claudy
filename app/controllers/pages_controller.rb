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
    # stays
    @stay_reservations = StayItemDate.all
      .includes(:stay)
      .where(direct_book: true)
      .where.not(stay: {status: [StayStatus::DECLINED, StayStatus::CANCELED], draft: true } )
      .between_times(@first, @last, field: :booking_date)
    
    @grouped_stay_reservations = @stay_reservations.to_a.group_by { |sr| sr.booking_date }
    
    # spaces
    space_reservations = @stay_reservations.where(booked_item_type: StayItem::SPACE)
    @grouped_spaces = space_reservations.to_a.group_by { |sr| sr.booking_date }
    # experiences
    exp_reservations = @stay_reservations.where(booked_item_type: StayItem::EXPERIENCE)
    @grouped_experiences = exp_reservations.to_a.group_by { |sr| sr.booking_date }

    # rental items TODO?

    # activities
    activities_without_stays = PublicActivity::Activity.where("created_at > ?", 14.days.ago).order(created_at: :desc)
      .where.not(trackable_type: 'Stay')
    stay_activities = Activity.stays_without_drafts.where("created_at > ?", 14.days.ago).order(created_at: :desc)
    @activities = (activities_without_stays + stay_activities).sort_by(&:created_at).reverse

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

    # stays
     @stay_reservations = StayItemDateDecorator.decorate_collection(StayItemDate.all
      .includes(:stay)
      .where(booking_date: @date)
      .where(stay: {status: StayStatus::CONFIRMED, draft: false } ))

    # rooms
    @stay_room_reservations = @stay_reservations.where(booked_item_type: StayItem::ROOM)
    Rails.logger.info("$$$$$$$$$ #{@stay_room_reservations}")

    # spaces
    @stay_space_reservations = @stay_reservations.where(booked_item_type: StayItem::SPACE)
    
    # experiences
    exp_reservations = @stay_reservations.where(booked_item_type: StayItem::EXPERIENCE)
    

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
      .where.not(booking: { status: "declined" })
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
