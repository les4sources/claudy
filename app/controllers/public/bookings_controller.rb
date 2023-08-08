class Public::BookingsController < Public::BaseController
  layout "public_sheet"

  def new
    @booking = Booking.new(
      booking_type: "lodging",
      adults: 0,
      children: 0,
      babies: 0,
      tier_lodgings: "neutre",
      tier_rooms: "neutre"
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
    @booking = Booking.find_by!(token: params[:token]).decorate
    @reservations_by_date = @booking.reservations.decorate.to_a.group_by { |r| r.date }
  rescue ActiveRecord::RecordNotFound
    raise ActionController::RoutingError.new('Not Found')
  end

  def edit_estimated_arrival
    @booking = Booking.find(params[:id])
  end

  def update_estimated_arrival
    @booking = Booking.find(params[:id])
    if @booking.update(booking_params)
      respond_to do |format|
        format.html { 
          redirect_to public_booking_path(@booking.token), 
                      notice: "Merci! Votre réservation a été mise à jour." 
        }
        format.turbo_stream
      end
    else
      render :edit_estimated_arrival, status: :unprocessable_entity
    end
  end

  private

  def booking_params
    params
      .require(:booking)
      .permit(
        :estimated_arrival
      )
  end
end
