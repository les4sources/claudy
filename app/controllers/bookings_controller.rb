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
    @booking = Booking.find_by!(id: params[:id])
    respond_to do |format|
      if @booking.update(booking_params)
        format.html { redirect_to @booking, notice: "La réservation a été mise à jour." }
        format.json { render :show, status: :ok, location: @booking }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @booking.errors, status: :unprocessable_entity }
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
        :firstname,
        :lastname,
        :phone,
        :email,
        :from_date,
        :to_date,
        :status,
        :adults,
        :children,
        :price,
        :payment_status,
        :payment_method,
        :bedsheets,
        :towels,
        :notes,
        room_ids: []
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
