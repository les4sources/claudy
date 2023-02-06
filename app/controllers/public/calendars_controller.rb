class Public::CalendarsController < Public::BaseController
  layout "public"

  def lodgings
    set_dates
    @lodgings = Lodging.all
    @reservations = Reservation.all
      .includes(:booking)
      .between_times(@first, @last, field: :date)
    # group bookings by day
    @upcoming_by_date = @reservations.to_a.group_by { |r| r.date }
  end

  def lodgings_modal
    set_dates
    @lodgings = Lodging.all
    @reservations = Reservation.all
      .includes(:booking)
      .between_times(@first, @last, field: :date)
    # group bookings by day
    @upcoming_by_date = @reservations.to_a.group_by { |r| r.date }
  end

  private

  def set_dates
    # get the date from params if there is one - for display AND to limit our query
    @date = params[:date] ? Date.parse(params[:date]) : Date.tomorrow
    if @date < Date.tomorrow
      @date = Date.tomorrow
    end
    @first = @date.beginning_of_month.beginning_of_week.beginning_of_day
    @last = @date.end_of_month.end_of_week.end_of_day
    # @dates = (@date.beginning_of_month..@date.end_of_month).map(&:to_date)
  end

end
