class BookingsController < BaseController
  breadcrumb "Hébergements", :bookings_path, match: :exact

  def index
    @bookings = BookingDecorator
      .decorate_collection(Booking.unscoped.current_and_future)
  end

  def past
    @bookings = BookingDecorator
      .decorate_collection(Booking.past.paginate(page: params[:page], per_page: 40))
  end

  def show
    @booking = Booking.unscoped.find_by!(id: params[:id]).decorate
    @reservations_by_date = @booking.reservations.decorate.to_a.group_by { |r| r.date }
    breadcrumb "Réservation ##{@booking.id}", booking_path(@booking), match: :exact
  end

  def new
    @booking = Booking.new(
      booking_type: "lodging",
      adults: 0,
      children: 0,
      babies: 0,
      platform: "direct",
      tier_lodgings: "neutre",
      tier_rooms: "neutre",
      from_date: params.fetch("date", nil)
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
      set_error_flash(service.booking, "<strong>Cette réservation n'a pas pu être enregistrée, merci de vérifier les éléments suivants:</strong><br>#{service.error_message}")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @booking = Booking.find_by!(id: params[:id])
    @booking.room_ids = @booking.reservations.map { |r| r.room_id }
    @booking.booking_type = @booking.lodging_id.nil? ? "rooms" : "lodging"
    @booking.tier_lodgings = @booking.tier_rooms = @booking.tier
    @lodgings = Lodging.all
  end

  def update
    service = Bookings::UpdateService.new(booking_id: params[:id])
    respond_to do |format|
      if service.run!(params)
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
    @booking.soft_delete!(validate: false)
    @booking.create_activity(:destroy)
    redirect_to bookings_url,
                status: :see_other,
                notice: "La réservation a été supprimée."
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "bookings",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end
end
