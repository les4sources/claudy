class Public::BookingsController < Public::BaseController
  layout "public_sheet"

  def new
    @booking = Booking.new
  end

  def create
    service = Bookings::CreateService.new
    if service.run(params)
      redirect_to service.booking,
                  notice: "Merci, votre demande de réservation a été enregistrée. Nous vous recontactons dans les 48 heures."
    else
      @booking = service.booking
      set_error_flash(service.booking, service.error_message)
      render :new
    end
  end

  def show
    # TODO add token to access booking based on token
    @booking = Booking.find_by(token: params[:token])
  end
end
