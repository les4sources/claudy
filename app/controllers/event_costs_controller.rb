# Les frais fixes d'un événement (epic #245, phase 1). Ils se déduisent de la
# recette AVANT le partage avec les organisateurs.
#
# Quatre gestes — ajouter, modifier, retirer, et reprendre une réservation
# d'espace — et une seule réponse : le bloc entier, remplacé en Turbo Stream.
class EventCostsController < BaseController
  before_action :get_event
  before_action :get_cost, only: %i[update destroy]

  def create
    @cost = @event.event_costs.build(cost_params.merge(kind: "other"))

    if @cost.save
      @cost = nil
      render_costs
    else
      render_costs(status: :unprocessable_entity)
    end
  end

  def update
    @cost.update(cost_params)
    render_costs(status: @cost.errors.any? ? :unprocessable_entity : :ok)
  end

  def destroy
    @cost.soft_delete!(validate: false)
    @cost = nil
    render_costs
  end

  # « Ajouter en frais » : la ligne reprend le prix PERSISTÉ de la réservation
  # d'espace, jamais un prix recalculé (règle Finances), et garde le lien vers
  # elle pour qu'on ne la compte pas deux fois.
  def from_space_booking
    booking = @event.space_bookings.find(params[:space_booking_id])

    @event.event_costs.create(
      label: "Espace — #{booking_label(booking)}",
      amount_cents: booking.price_cents.to_i,
      kind: "space",
      source: booking
    )

    render_costs
  end

  private

  def get_event = @event = Event.find(params[:event_id])

  def get_cost = @cost = @event.event_costs.find(params[:id])

  def cost_params
    permitted = params.require(:event_cost).permit(:label, :amount, :amount_cents)
    amount = permitted.delete(:amount)
    permitted[:amount_cents] = euros_to_cents(amount) if amount.present?
    permitted
  end

  # Saisie en euros, virgule tolérée — c'est celle qu'on tape en français.
  def euros_to_cents(value)
    (value.to_s.strip.tr(",", ".").to_f * 100).round
  end

  def booking_label(booking)
    dates = [booking.from_date, booking.to_date].compact.map { |d| l(d, format: :short) }.uniq
    spaces = booking.spaces.map(&:name).uniq.join(", ")
    [spaces.presence, dates.join(" → ").presence].compact.join(", ").presence ||
      "réservation ##{booking.id}"
  end

  def render_costs(status: :ok)
    @cost ||= EventCost.new(event: @event)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "event-costs",
          partial: "events/costs",
          locals: { event: @event, cost: @cost }
        ), status: status
      end
      format.html { redirect_to event_path(@event, tab: "comptabilite") }
    end
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "events"
    )
    @settings_view = true
  end
end
