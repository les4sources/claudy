class AccountingController < BaseController
  def index
    @bookings = BookingDecorator
      .decorate_collection(
        Booking.where(tier: "non défini", status: ["confirmed", "pending"])
      )
    @space_bookings = SpaceBookingDecorator
      .decorate_collection(
        SpaceBooking.where(tier: "non défini", status: ["confirmed", "pending"])
      )
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "accounting"
    )
    @accounting_view = true
  end
end
