class PagesController < BaseController
  def calendar
    set_dates
    # events = Event.all
    #   .includes(:event_category)
    #   .between_times(@first, @last)
    # @grouped_events = {}
    # events.each do |event|
    #   (event.starts_at.to_date..event.ends_at.to_date).each do |date|
    #     @grouped_events[date] ||= []
    #     @grouped_events[date] << event
    #   end
    # end
    @space_reservations = SpaceReservation.all
      .includes(:space_booking)
      .where.not(space_booking: { status: "declined" })
      .between_times(@first, @last, field: :date)
    # group bookings by day
    @grouped_space_reservations = @space_reservations.to_a.group_by { |sr| sr.date }
    @reservations = Reservation.all
      .includes(:booking)
      .where.not(booking: { status: "declined" })
      .between_times(@first, @last, field: :date)
    # group bookings by day
    @grouped_reservations = @reservations.to_a.group_by { |r| r.date }
  end

  def other_bookings
    @reservations = Reservation.all
      .includes(:booking)
      .where.not(booking: { status: "declined" })
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
      .between_times(Date.parse(params[:from_date]), Date.parse(params[:to_date]) - 1.day, field: :date)
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
