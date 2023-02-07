class Public::BookingsController < Public::BaseController
  layout "public_sheet"

  def new
    @booking = Booking.new(
      booking_type: "lodging",
      adults: 0,
      children: 0
    )
  end

  def create
    @service = Public::Bookings::CreateService.new
    if @service.run(params)
      redirect_to "/public/reservation/#{@service.booking.token}",
                  notice: "Merci, votre demande de réservation est enregistrée. Vous allez recevoir un email de confirmation de notre part et nous vous recontactons très prochainement."
    else
      @booking = @service.booking
      set_error_flash(@service.booking, "<strong>Votre réservation n'a pas pu être enregistrée, merci de vérifier les éléments suivants:</strong><br>#{@service.error_message}")
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # TODO add token to access booking based on token
    @booking = Booking.find_by(token: params[:token]).decorate
    @reservations_by_date = @booking.reservations.decorate.to_a.group_by { |r| r.date }
  end
end
