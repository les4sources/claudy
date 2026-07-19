class Public::BookingsController < Public::BaseController
  layout "public_sheet"

  # Épic #81, Phase 9 — demande de réservation publique legacy retirée.
  # `#new`/`#create` supprimés : le funnel natif /reservation est le seul point
  # d'entrée public de création. `#show` (page client token) et
  # `edit_estimated_arrival`/`update_estimated_arrival` (services aux clients
  # existants) restent en place.

  def show
    @booking = Booking.find_by!(token: params[:token]).decorate
    @reservations_by_date = @booking.reservations.decorate.to_a.group_by { |r| r.date }
    record_page_view(@booking) unless params[:donottrack].present?
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

  # Enregistre une consultation de la page web privée du client (issue #16).
  # Le tracking ne doit jamais faire échouer l'affichage de la page.
  def record_page_view(booking)
    booking.object.page_views.create(
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  rescue StandardError => e
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  def booking_params
    params
      .require(:booking)
      .permit(
        :estimated_arrival
      )
  end
end
