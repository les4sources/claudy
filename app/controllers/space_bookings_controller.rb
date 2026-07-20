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

  # Édition unifiée (issue #99, aboutissement epic #81 Phase 8) : `#edit` est une
  # PURE redirection — l'écran d'édition legacy n'existe plus. Cas résiduel
  # (séjour soft-deleté à la main) : on renvoie sur la fiche `#show` avec alerte.
  def edit
    @space_booking = SpaceBooking.find_by!(id: params[:id])

    if (stay = @space_booking.stay)
      redirect_to edit_stay_path(stay)
    else
      redirect_to space_booking_path(@space_booking),
                  alert: "Cette résa d'espace n'est plus rattachée à un séjour — relancer rake stays:backfill_missing."
    end
  end

  # `#update` retiré (issue #99) : le form legacy n'existe plus, aucune
  # soumission possible. L'édition passe exclusivement par le séjour.

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
