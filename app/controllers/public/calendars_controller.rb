class Public::CalendarsController < Public::BaseController
  layout "public"

  # « Coworking » a été RETIRÉ de ce calendrier (amendement Michael 2026-07-21,
  # epic #126) : les 3 bureaux vivent désormais dans le domaine coworking
  # (`CoworkingPack` / `CoworkingReservation`), qui en est l'unique source de
  # vérité. L'historique `SpaceBooking` de l'espace reste intact et lisible.
  CALENDAR_SPACE_NAMES = ["Grande Salle", "Petite Salle", "Cuisine professionnelle", "Bois"].freeze

  def lodgings
    set_dates
    @lodgings = Lodging.where(available_for_bookings: true)
    @spaces = Space.where(name: CALENDAR_SPACE_NAMES)
    @reservations = Reservation.all
      .includes(:booking)
      .between_times(@first, @last, field: :date)
    # group bookings by day
    @upcoming_by_date = @reservations.to_a.group_by { |r| r.date }
  end

  def lodgings_modal
    set_dates
    @lodgings = Lodging.where(available_for_bookings: true)
    @spaces = Space.where(name: CALENDAR_SPACE_NAMES)
    @reservations = Reservation.all
      .includes(:booking)
      .between_times(@first, @last, field: :date)
    # group bookings by day
    @upcoming_by_date = @reservations.to_a.group_by { |r| r.date }
  end

  private

  def set_dates
    # get the date from params if there is one - for display AND to limit our query
    @date = params[:date] ? Date.parse(params[:date]) : Date.tomorrow
    if @date < Date.tomorrow
      @date = Date.tomorrow
    end
    @first = @date.beginning_of_month.beginning_of_week.beginning_of_day
    @last = @date.end_of_month.end_of_week.end_of_day
    # @dates = (@date.beginning_of_month..@date.end_of_month).map(&:to_date)
  end

end
