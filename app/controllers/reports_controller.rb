class ReportsController < BaseController
  def index
    @year = params.fetch(:year, Time.now.year).to_i
    bookings = Booking.where(
      status: "confirmed", 
      from_date: Date.new(@year, 1, 1).beginning_of_year..Date.new(@year, 1, 1).end_of_year
    )
    space_bookings = SpaceBooking.where(
      status: "confirmed", 
      from_date: Date.new(@year, 1, 1).beginning_of_year..Date.new(@year, 1, 1).end_of_year
    )

    @revenues_by_month_for_bookings = 
      bookings.group(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
              .order(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
              .sum(:price_cents)
    @revenues_by_month_for_space_bookings = 
      space_bookings.group(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
                    .order(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
                    .sum(:price_cents)
    @revenues_by_platform = 
      bookings.group(:platform)
              .sum(:price_cents)
    @lodgings = LodgingDecorator.decorate_collection(
      Lodging.where(show_on_reports: true)
    )
    @spaces = SpaceDecorator.decorate_collection(
      Space.all
    )
  end

  def lodging
    @lodging = LodgingDecorator.new(Lodging.find(params[:id]))
    @year = params.fetch(:year, Time.now.year).to_i

  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "reports"
    )
    @reports_view = true
  end
end
