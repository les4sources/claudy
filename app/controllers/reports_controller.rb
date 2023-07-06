class ReportsController < BaseController
  def index
    @start_date, @end_date = parse_date_range
    revenue_by_month_for_bookings = 
      Booking.where(status: "confirmed", from_date: @start_date..@end_date)
             .group('(EXTRACT(YEAR FROM from_date))::integer')
             .group('(EXTRACT(MONTH FROM from_date))::integer')
             .order('2 DESC, 3 DESC')
             .sum(:price_cents)
    @revenue_by_month_for_bookings = revenue_by_month_for_bookings.transform_values { |v| v / 100.0 }
    revenue_by_month_for_space_bookings = 
      SpaceBooking.where(status: "confirmed", from_date: @start_date..@end_date)
             .group('(EXTRACT(YEAR FROM from_date))::integer')
             .group('(EXTRACT(MONTH FROM from_date))::integer')
             .order('2 DESC, 3 DESC')
             .sum(:price_cents)
    @revenue_by_month_for_space_bookings = revenue_by_month_for_space_bookings.transform_values { |v| v / 100.0 }
  end

  private

  def parse_date_range
    if params[:start_date] && params[:end_date]
      [Date.parse(params[:start_date]), Date.parse(params[:end_date])]
    else
      [Date.yesterday.beginning_of_year, Date.today + 6.months]
    end
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "reports"
    )
  end
end
