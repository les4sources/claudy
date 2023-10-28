class ReportsController < BaseController
  def index
    @year = params.fetch(:year, Time.now.year).to_i
    @revenues_by_month_for_bookings = 
      Booking.where(status: 'confirmed')
             .where("EXTRACT(YEAR FROM from_date)::integer = ?", @year)
             .group(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
             .order(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
             .sum(:price_cents)
    @revenues_by_month_for_space_bookings = 
      SpaceBooking.where(status: 'confirmed')
                  .where("EXTRACT(YEAR FROM from_date)::integer = ?", @year)
                  .group(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
                  .order(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
                  .sum(:price_cents)
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "reports"
    )
  end
end
