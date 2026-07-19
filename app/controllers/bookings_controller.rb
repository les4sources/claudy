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
  end

  # Épic #81, Phase 9 — création directe retirée. `#new`/`#create` supprimés :
  # tout nouveau booking naît désormais du séjour (`StaysController`) ou du funnel
  # natif. La duplication est disponible au niveau du séjour
  # (`new_stay_path(duplicate_from:)`).

  def edit
    @booking = Booking.find_by!(id: params[:id])

    # Édition unifiée (epic #81, Phase 8) : l'édition d'un booking passe désormais
    # par le form séjour. Un vieux favori / lien email vers /bookings/:id/edit
    # atterrit au bon endroit. Sans Stay vivant (backfill Phase 1 pas encore
    # tourné en prod), on tombe sur l'écran legacy ci-dessous — fallback orphelin.
    if (stay = @booking.stay)
      return redirect_to edit_stay_path(stay)
    end

    @booking.room_ids = @booking.reservations.map { |r| r.room_id }
    @booking.booking_type = @booking.lodging_id.nil? ? "rooms" : "lodging"
    @booking.tier_lodgings = @booking.tier_rooms = @booking.tier
    @booking.payments.build
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
    @booking.soft_delete!(validate: false)
    @booking.create_activity(:destroy)
    redirect_to bookings_url,
                status: :see_other,
                notice: "La réservation a été supprimée."
  end

  def search
    if params[:booking]
      @bookings = BookingDecorator.decorate_collection(
        Booking.search(params[:booking][:query])
      )
      @space_bookings = SpaceBookingDecorator.decorate_collection(
        SpaceBooking.search(params[:booking][:query])
      )
    else
      @bookings = Booking.none
      @space_bookings = SpaceBooking.none
    end
    @accounting_view = true
    render :search_results
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
