module Portal
  # Section « Coworking » du portail client (epic #126, Phase 3).
  #
  # Le client voit son solde de journées, achète des packs (Stripe Checkout) et
  # pose ses journées sur un calendrier mensuel lundi-vendredi. Tout part de
  # `current_portal_customer` : aucun identifiant client dans l'URL.
  class CoworkingController < Portal::BaseController
    before_action :require_coworking_access

    PACK_OPTIONS = CoworkingPack::DAYS_OPTIONS

    def index
      @packs = current_portal_customer.coworking_packs.ordered.includes(:payments)
      @credits = @packs.select(&:paid?).sum(&:days_remaining)
      @pack_options = PACK_OPTIONS.map do |days|
        { days: days, price_cents: Pricing::Catalog.coworking_pack_cents(days) }
      end
      # Packs payés dont les crédits vont bientôt périmer : signalés en haut du
      # portail (« 3 jours expirent le 12/08 »).
      @expiring_packs = @packs.select { |pack| pack.credits_expiring_soon? }
      # Historique des journées déjà passées, plus récentes d'abord.
      @past_reservations = current_portal_customer.coworking_reservations
                                                  .where("date < ?", Date.current)
                                                  .order(date: :desc)
      build_calendar
    end

    # POST /portail/coworking/achat — démarre un achat en ligne et redirige vers
    # Stripe Checkout. Le formulaire porte `data-turbo=false` (leçon PR #104) :
    # une redirection externe sous Turbo Drive produit un clic mort.
    def purchase
      service = Coworking::StartOnlinePurchase.new(
        customer: current_portal_customer,
        days_total: params[:days_total],
        return_url: portal_coworking_url
      )

      if service.run
        redirect_to service.checkout_url, allow_other_host: true
      else
        redirect_to portal_coworking_path, alert: service.error_message
      end
    end

    private

    # Un prospect sans compte doit pouvoir acheter : on l'envoie vers la
    # connexion en CONTEXTE coworking (email → OTP → compte créé à la connexion),
    # pas vers la connexion « Mes séjours ».
    def require_coworking_access
      return if portal_signed_in?

      redirect_to portal_path(context: "coworking"), alert: t("portal.session.coworking_required")
    end

    def build_calendar
      @month = parse_month(params[:month])
      @prev_month = @month.prev_month
      @next_month = @month.next_month
      range = @month.beginning_of_month..@month.end_of_month

      occupancy = CoworkingReservation.between(range.first, range.last).group(:date).count
      mine = current_portal_customer.coworking_reservations
                                    .between(range.first, range.last)
                                    .index_by(&:date)

      @weeks = build_weeks(@month, occupancy, mine)
    end

    # Grille par semaines (lignes), lundi→vendredi (colonnes). Les cases hors du
    # mois sont nil (rendues vides) pour garder l'alignement.
    def build_weeks(month, occupancy, mine)
      first = month.beginning_of_month
      last = month.end_of_month
      # On démarre au lundi de la semaine du 1er.
      cursor = first - ((first.wday + 6) % 7)
      weeks = []

      while cursor <= last
        week = (0..4).map do |offset|
          date = cursor + offset
          next nil if date < first || date > last

          day_cell(date, occupancy.fetch(date, 0), mine[date])
        end
        weeks << week if week.any?
        cursor += 7.days
      end

      weeks
    end

    def day_cell(date, taken, reservation)
      {
        date: date,
        taken: taken,
        remaining: [CoworkingReservation::DAILY_CAPACITY - taken, 0].max,
        full: taken >= CoworkingReservation::DAILY_CAPACITY,
        past: date < Date.current,
        reservation: reservation,
        cancellable: reservation.present? && Coworking::CancelDay.cancellable?(date)
      }
    end

    def parse_month(raw)
      Date.strptime(raw.to_s, "%Y-%m").beginning_of_month
    rescue ArgumentError, TypeError
      Date.current.beginning_of_month
    end
  end
end
