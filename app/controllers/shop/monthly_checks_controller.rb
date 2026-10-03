module Shop
  # Le contrôle mensuel des carnets (epic #359, phase 5).
  #
  # Une fois par mois, en une minute : trois totaux par carnet (Épicerie,
  # Boulangerie), Claudy met en face ce que la banque a reçu, et l'écart se
  # fige à la validation. Les espèces déclarées servent ensuite à ventiler la
  # « Caisse épicerie » du mois entre les trois carnets — sur proposition,
  # jamais d'office.
  class MonthlyChecksController < BaseController
    breadcrumb "Carnets de l'épicerie", :shop_settings_path
    breadcrumb "Contrôle mensuel", :shop_monthly_checks_path, match: :exact

    before_action :load_month, except: :index

    def index
      checks = ShopMonthlyCheck.includes(:validated_by).to_a
      @checks_by_month = checks.group_by(&:period_month)
      current = Date.current.beginning_of_month
      @months = (@checks_by_month.keys + [current, current.prev_month]).uniq.sort.reverse
      validated = checks.select(&:validated?)
      @cumulative = ShopMonthlyCheck::CHANNELS.index_with do |channel|
        validated.select { |check| check.channel == channel }.sum(&:gap_cents)
      end
    end

    def show
      breadcrumb I18n.l(@month, format: "%B %Y").capitalize, shop_monthly_check_path(month_param), match: :exact
      existing = ShopMonthlyCheck.for_month(@month).index_by(&:channel)
      @checks = ShopMonthlyCheck::CHANNELS.index_with do |channel|
        existing[channel] || ShopMonthlyCheck.new(channel: channel, period_month: @month)
      end
      @ventilation = Shop::VentilateGroceryCash.new(month: @month)
      @consignment_reports = ConsignmentReport.for_month(@month).includes(:consignor, :consignment_report_lines)
      @cash_counts = CashCount.where(counted_on: @month..@month.end_of_month).ordered
    end

    def update
      check = Shop::RecordMonthlyCheck.new(
        channel: params[:channel], month: @month, attributes: check_params,
        validate: params[:validate].present?, user: current_user
      ).run!
      notice = if check.validated?
                 "Contrôle #{check.notebook_label} validé : l'écart est figé."
               else
                 "Contrôle #{check.notebook_label} enregistré en brouillon."
               end
      redirect_to shop_monthly_check_path(month_param), notice: notice
    rescue ActiveRecord::RecordInvalid, Shop::RecordMonthlyCheck::AlreadyValidated => e
      redirect_to shop_monthly_check_path(month_param), alert: e.message
    end

    def ventilate
      count = Shop::VentilateGroceryCash.new(month: @month, whodunnit: current_user&.email).apply!
      notice = count.zero? ? "La caisse épicerie du mois était déjà ventilée." : "#{count} ligne(s) de caisse ventilée(s)."
      redirect_to shop_monthly_check_path(month_param), notice: notice
    rescue Shop::VentilateGroceryCash::NotReady, Shop::VentilateGroceryCash::MonthClosed,
           Accounting::UnpostCashEntry::ClosedFiscalYear, Accounting::PostCashEntry::NotFullyAllocated,
           ActiveRecord::RecordInvalid => e
      redirect_to shop_monthly_check_path(month_param), alert: e.message
    end

    private

    def load_month
      @month = Date.strptime(params[:month], "%Y-%m").beginning_of_month
    rescue Date::Error
      redirect_to shop_monthly_checks_path, alert: "Mois introuvable."
    end

    def month_param = @month.strftime("%Y-%m")

    # Montants saisis en euros, virgule tolérée.
    def check_params
      raw = params.fetch(:shop_monthly_check, {}).permit(:sheets_total, :transfer_total, :cash_total,
                                                          :sheet_numbers, :notes)
      {
        sheets_total_cents: euros_to_cents(raw[:sheets_total]),
        transfer_total_cents: euros_to_cents(raw[:transfer_total]),
        cash_total_cents: euros_to_cents(raw[:cash_total]),
        sheet_numbers: raw[:sheet_numbers].to_s.strip.presence,
        notes: raw[:notes].to_s.strip.presence
      }
    end

    def euros_to_cents(raw) = (raw.to_s.delete(" ").tr(",", ".").to_f * 100).round.abs

    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(active_primary: "settings", active_secondary: "consignors")
      @settings_view = true
    end
  end
end
