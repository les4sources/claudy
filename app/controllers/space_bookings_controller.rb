class SpaceBookingsController < BaseController
  breadcrumb "Espaces", :space_bookings_path, match: :exact

  def index
    @space_bookings = SpaceBookingDecorator
      .decorate_collection(
        SpaceBooking.current_and_future
          .includes(:event)
      )
  end

  def past
    @space_bookings = SpaceBookingDecorator
      .decorate_collection(SpaceBooking.past.paginate(page: params[:page], per_page: 40))
  end

  def show
    @space_booking = SpaceBooking
      .find_by!(id: params[:id])
      .decorate
    @space_reservations_by_date = @space_booking.space_reservations.to_a.group_by { |sr| sr.date }
    breadcrumb "Réservation ##{@space_booking.id}", space_booking_path(@space_booking), match: :exact
  end

  def new
    @space_booking = SpaceBooking.new(
      paid_amount: 0,
      advance_amount: 0,
      deposit_amount: 0
    )
    @spaces = Space.all
  end

  def create
    service = SpaceBookings::CreateService.new
    if service.run(params)
      redirect_to service.space_booking,
                  notice: "Merci, la réservation a été enregistrée."
    else
      @space_booking = service.space_booking
      set_error_flash(service.space_booking, "<strong>Cette réservation n'a pas pu être enregistrée, merci de vérifier les éléments suivants:</strong><br>#{service.error_message}")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @space_booking = SpaceBooking.find_by!(id: params[:id])
    @space_booking.space_ids = @space_booking.space_reservations.map { |sr| sr.space_id }
    @spaces = Space.all
  end

  def update
    service = SpaceBookings::UpdateService.new(space_booking_id: params[:id])
    respond_to do |format|
      if service.run(params)
        format.html { redirect_to service.space_booking, notice: "La réservation a été mise à jour." }
        format.json { render :show, status: :ok, location: service.space_booking }
      else
        format.html { 
          @space_booking = service.space_booking
          byebug
          render :edit, 
                 status: :unprocessable_entity,
                 alert: service.error_message
        }
        format.json { render json: service.error_message, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @space_booking = SpaceBooking.find_by!(id: params[:id])
    @space_booking.destroy
    redirect_to space_bookings_url,
                status: :see_other,
                notice: "La réservation a été supprimée."
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "space_bookings",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end
end
