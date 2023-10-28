class ReportsController < BaseController
  def index
    @year = params.fetch(:year, Time.now.year.to_s)
    @revenues_by_month_for_bookings = Booking.where(status: 'confirmed')
                                .where('strftime("%Y", from_date) = ?', @year)
                                .group(Arel.sql("strftime('%m', from_date)"))
                                .order(Arel.sql("strftime('%m', from_date)"))
                                .sum(:price_cents)
    @revenues_by_month_for_space_bookings = SpaceBooking.where(status: 'confirmed')
                                .where('strftime("%Y", from_date) = ?', @year)
                                .group(Arel.sql("strftime('%m', from_date)"))
                                .order(Arel.sql("strftime('%m', from_date)"))
                                .sum(:price_cents)
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "reports"
    )
  end
end
