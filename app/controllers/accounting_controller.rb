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
    @stays_without_price = StayDecorator.decorate_collection(
      Stay.where(status: "confirmed", final_price_cents: 0, draft: false)
    )
    @stays_with_requested_invoice = StayDecorator.decorate_collection(
      Stay.where(status: "confirmed", invoice_status: "requested", draft: false)
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
