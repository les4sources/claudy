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
    @revenues_by_platform = 
      Booking.where(status: 'confirmed', from_date: Date.new(@year, 1, 1).beginning_of_year..Date.new(@year, 1, 1).end_of_year)
                  .group(:platform)
                  .sum(:price_cents)
    @lodgings = LodgingDecorator.decorate_collection(
      Lodging.where(show_on_reports: true)
    )
    @spaces = SpaceDecorator.decorate_collection(
      Space.all
    )
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "reports"
    )
  end
end
