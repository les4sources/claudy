class Public::SpaceBookingsController < Public::BaseController
  layout "public_sheet"

  def show
    @space_booking = SpaceBooking.find_by(token: params[:token]).decorate
    @space_reservations_by_date = @space_booking.space_reservations.decorate.to_a.group_by { |sr| sr.date }
  end
end
