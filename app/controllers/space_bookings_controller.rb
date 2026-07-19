class SpaceBookingsController < BaseController
  breadcrumb "Espaces", :space_bookings_path, match: :exact

  def index
    @space_bookings = SpaceBookingDecorator
      .decorate_collection(
        SpaceBooking
          .unscoped
          .current_and_future
          .includes(:event)
      )
  end

  def past
    @space_bookings = SpaceBookingDecorator
      .decorate_collection(SpaceBooking.past.paginate(page: params[:page], per_page: 40))
  end

  def show
    @space_booking = SpaceBooking
      .unscoped
      .find_by!(id: params[:id])
      .decorate
    @space_reservations_by_date = @space_booking.space_reservations.to_a.group_by { |sr| sr.date }
  end

  # Épic #81, Phase 9 — création directe retirée. `#new`/`#create` supprimés :
  # toute nouvelle résa d'espace naît désormais du séjour (`StaysController`). La
  # duplication est disponible au niveau du séjour (`new_stay_path(duplicate_from:)`).

  def edit
    @space_booking = SpaceBooking.find_by!(id: params[:id])

    # Édition unifiée (epic #81, Phase 8) : l'édition d'une résa d'espace passe
    # désormais par le form séjour. Sans Stay vivant (backfill Phase 1 pas encore
    # tourné en prod), on tombe sur l'écran legacy ci-dessous — fallback orphelin.
    if (stay = @space_booking.stay)
      return redirect_to edit_stay_path(stay)
    end

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
    @space_booking.soft_delete!(validate: false)
    @space_booking.create_activity(:destroy)
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
