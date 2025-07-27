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
    set_revenues_statistics(bookings, space_bookings)
    set_beds_statistics(bookings)
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

  def set_beds_statistics(bookings)
    @beds_used_per_month = {}
    (1..12).each do |month|
      @beds_used_per_month[month] = 0
    end

    bookings.each do |booking|
      num_nights = (booking.to_date - booking.from_date).to_i
      beds_used_per_night = booking.adults + booking.children
      (booking.from_date..booking.to_date).each do |date|
        @beds_used_per_month[date.month] += beds_used_per_night
      end
    end
    @beds_used_per_year = @beds_used_per_month.values.sum
  end

  def set_revenues_statistics(bookings, space_bookings)
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
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "reports"
    )
    @reports_view = true
  end
end
