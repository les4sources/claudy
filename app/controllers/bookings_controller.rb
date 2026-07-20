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

  # Édition unifiée (issue #99, aboutissement epic #81 Phase 8) : `#edit` est une
  # PURE redirection — l'écran d'édition legacy n'existe plus. Un vieux favori /
  # lien email vers /bookings/:id/edit atterrit sur le form séjour. Cas résiduel
  # (séjour soft-deleté à la main, avant que le backfill ait tourné) : on renvoie
  # sur la fiche `#show` avec une alerte plutôt que de servir un form disparu.
  def edit
    @booking = Booking.find_by!(id: params[:id])

    if (stay = @booking.stay)
      redirect_to edit_stay_path(stay)
    else
      redirect_to booking_path(@booking),
                  alert: "Ce booking n'est plus rattaché à un séjour — relancer rake stays:backfill_missing."
    end
  end

  # `#update` retiré (issue #99) : le form legacy n'existe plus, aucune
  # soumission possible. L'édition passe exclusivement par le séjour.

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
