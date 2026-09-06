class ReportsController < BaseController
  def index
    @year = params.fetch(:year, Time.now.year).to_i
    bookings = Booking.where(
      status: "confirmed", 
      from_date: Date.new(@year, 1, 1).beginning_of_year..Date.new(@year, 1, 1).end_of_year
    )
    space_bookings = SpaceBooking.where(
      status: "confirmed", 
      from_date: Date.new(@year, 1, 1).beginning_of_year..Date.new(@year, 1, 1).end_of_year
    )
    set_revenues_statistics(bookings, space_bookings)
    # Cuisine (epic #219, phase 5) : le CA des repas, buffets et apéros entre
    # dans le reporting mensuel à côté des hébergements et des espaces.
    @revenues_by_month_for_meals = Reports::KitchenRevenue.revenue_by_month(@year)
    set_beds_statistics(bookings)
    set_coworking_statistics(@year)
    @lodgings = LodgingDecorator.decorate_collection(
      Lodging.where(show_on_reports: true)
    )
    @spaces = SpaceDecorator.decorate_collection(
      Space.all
    )
  end

  # Reporting > Cuisine (epic #219, phase 5) : ce que la compta doit lire chaque
  # mois pour savoir ce qu'elle doit à qui, sur la plage de son choix.
  def kitchen
    @from = parse_report_date(params[:from], Date.current.beginning_of_month)
    @to   = parse_report_date(params[:to], Date.current.end_of_month)
    @to, @from = @from, @to if @to < @from
    @report = Reports::KitchenRevenue.new(from: @from, to: @to)

    respond_to do |format|
      format.html
      format.csv do
        send_data Reports::KitchenCsv.new(@report).to_csv,
                  filename: "cuisine-#{@from.iso8601}-#{@to.iso8601}.csv",
                  type: "text/csv; charset=utf-8"
      end
    end
  end

  def lodging
    @lodging = LodgingDecorator.new(Lodging.find(params[:id]))
    @year = params.fetch(:year, Time.now.year).to_i

  end

  private

  def parse_report_date(value, fallback)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    fallback
  end

  def set_beds_statistics(bookings)
    @beds_used_per_month = {}
    (1..12).each do |month|
      @beds_used_per_month[month] = 0
    end

    bookings.each do |booking|
      num_nights = (booking.to_date - booking.from_date).to_i
      beds_used_per_night = booking.adults + booking.children
      (booking.from_date..(booking.to_date-1)).each do |date|
        @beds_used_per_month[date.month] += beds_used_per_night
      end
    end
    @beds_used_per_year = @beds_used_per_month.values.sum
  end

  # Vue d'ensemble coworking (epic #126, Phase 4) — domaine indépendant des
  # séjours, présenté à part dans le Reporting. Trois chiffres : occupation
  # (journées-bureau réservées), CA coworking (packs PAYÉS achetés dans l'année)
  # et l'état courant des packs actifs. `paid?` et `days_remaining` sont
  # calculés en Ruby ; les packs/réservations soft-deletés (remboursés/annulés)
  # sont d'office exclus par le default_scope.
  def set_coworking_statistics(year)
    year_start = Date.new(year, 1, 1).beginning_of_year
    year_end = Date.new(year, 1, 1).end_of_year

    # Occupation : journées-bureau réservées, par mois.
    @coworking_days_by_month =
      CoworkingReservation.between(year_start.to_date, year_end.to_date)
                          .group(Arel.sql("EXTRACT(MONTH FROM date)::integer"))
                          .count
    @coworking_days_total = @coworking_days_by_month.values.sum

    # CA coworking : packs payés achetés dans l'année, ventilés par mois d'achat.
    paid_packs = CoworkingPack.where(purchased_at: year_start..year_end).select(&:paid?)
    @coworking_revenue_by_month = Hash.new(0)
    paid_packs.each { |pack| @coworking_revenue_by_month[pack.purchased_at.month] += pack.price_cents }
    @coworking_revenue_total = @coworking_revenue_by_month.values.sum

    # État courant, tous millésimes confondus : packs vivants non expirés et
    # payés, et crédits encore disponibles.
    active_paid = CoworkingPack.active.select(&:paid?)
    @coworking_active_packs = active_paid.size
    @coworking_credits_remaining = active_paid.sum(&:days_remaining)
  end

  def set_revenues_statistics(bookings, space_bookings)
    @revenues_by_month_for_bookings = 
      bookings.group(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
              .order(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
              .sum(:price_cents)
    @revenues_by_month_for_space_bookings = 
      space_bookings.group(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
                    .order(Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
                    .sum(:price_cents)
    @revenues_by_platform = 
      bookings.group(:platform)
              .sum(:price_cents)
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "reports"
    )
    @reports_view = true
    @home_view = true
  end
end
