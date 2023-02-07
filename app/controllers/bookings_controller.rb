class BookingsController < BaseController
  breadcrumb "Réservations", :bookings_path, match: :exact

  def index
    @bookings = BookingDecorator
      .decorate_collection(Booking.current_and_future)
  end

  def past
    @bookings = BookingDecorator
      .decorate_collection(Booking.past.paginate(page: params[:page], per_page: 40))
  end

  def show
    @booking = Booking.find_by!(id: params[:id]).decorate
    @reservations_by_date = @booking.reservations.decorate.to_a.group_by { |r| r.date }
    breadcrumb "Réservation ##{@booking.id}", booking_path(@booking), match: :exact
  end

  def new
    @booking = Booking.new(
      booking_type: "lodging",
      adults: 0,
      children: 0,
      platform: "direct"
    )
    @lodgings = Lodging.all
  end

  def create
    service = Bookings::CreateService.new
    if service.run(params)
      redirect_to service.booking,
                  notice: "Merci, la réservation a été enregistrée."
    else
      @booking = service.booking
      render :new, alert: service.error_message
    end
  end

  def edit
    @booking = Booking.find_by!(id: params[:id])
    @booking.room_ids = @booking.reservations.map { |r| r.room_id }
    @booking.booking_type = @booking.lodging_id.nil? ? "rooms" : "lodging"
    @lodgings = Lodging.all
  end

  def update
    service = Bookings::UpdateService.new(booking_id: params[:id])
    respond_to do |format|
      if service.run(params)
        format.html { redirect_to service.booking, notice: "La réservation a été mise à jour." }
        format.json { render :show, status: :ok, location: service.booking }
      else
        format.html { 
          @booking = service.booking
          render :edit, 
                 status: :unprocessable_entity,
                 alert: service.error_message
        }
        format.json { render json: service.error_message, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @booking = Booking.find_by!(id: params[:id])
    @booking.destroy
    redirect_to bookings_url,
                status: :see_other,
                notice: "La réservation a été supprimée."
  end

  private

  def booking_params
    params
      .require(:booking)
      .permit(
        :adults,
        :bedsheets,
        :booking_type,
        :children,
        :email,
        :estimated_arrival,
        :firstname,
        :from_date,
        :group_name,
        :invoice_wanted,
        :lastname,
        :lodging_id,
        :notes,
        :option_babysitting,
        :option_bread,
        :option_discgolf,
        :option_partyhall,
        :payment_method,
        :payment_status,
        :platform,
        :phone,
        :price,
        :shown_price_cents,
        :status,
        :tier,
        :to_date,
        :towels,
        room_ids: [],
      )
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "bookings",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end
end
