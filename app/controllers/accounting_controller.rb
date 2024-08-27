class AccountingController < BaseController
  def index
    @bookings = BookingDecorator
      .decorate_collection(
        Booking.where(tier: "non défini", status: ["confirmed", "pending"])
      )
    @bookings_with_requested_invoice = BookingDecorator
      .decorate_collection(
        Booking.where(status: "confirmed", invoice_status: "requested")
      )
    @space_bookings = SpaceBookingDecorator
      .decorate_collection(
        SpaceBooking.where(tier: "non défini", status: ["confirmed", "pending"])
      )
    @space_bookings_with_requested_invoice = SpaceBookingDecorator
      .decorate_collection(
        SpaceBooking.where(status: "confirmed", invoice_status: "requested")
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
