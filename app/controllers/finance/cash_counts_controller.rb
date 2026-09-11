module Finance
  # Comptabilité > Caisse > Comptages (epic #243, phase 3).
  #
  # Vingt secondes, une grille de dénominations, et la caisse dit si elle est
  # juste. L'écran n'existe que pour rendre le geste assez court pour être fait
  # chaque semaine : c'est l'absence de comptage régulier, pas la malhonnêteté,
  # qui a produit −628 € d'écart introuvable.
  class CashCountsController < Finance::AccountingBaseController
    before_action :get_account
    before_action :get_count, only: %i[edit update]

    breadcrumb "Caisse", :finance_cash_sheet_path, match: :exact
    breadcrumb "Comptages", :finance_cash_counts_path, match: :exact

    def index
      @counts = CashCount.ordered.includes(:cash_account, :counted_by, :adjustment_cash_entry)
    end

    def new
      @count = CashCount.new(cash_account: @account, counted_on: Date.current)
      @expected_cents = expected_for(@count.counted_on)
    end

    def edit
      @expected_cents = expected_for(@count.counted_on)
    end

    def create
      @count = record!
      after_record(@count)
    rescue ActiveRecord::RecordInvalid, Finance::RecordCashCount::MissingResolution,
           Finance::RecordCashCount::MissingAccount,
           Finance::RecordCashCount::MissingDifferenceAccount,
           Finance::RecordCashLine::MonthClosed, Date::Error => e
      @count = CashCount.new(cash_account: @account, counted_on: counted_on, comment: params.dig(:cash_count, :comment))
      @expected_cents = expected_for(@count.counted_on)
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    def update
      @count = record!(@count)
      after_record(@count)
    rescue ActiveRecord::RecordInvalid, Finance::RecordCashCount::MissingResolution,
           Finance::RecordCashCount::AlreadyValidated,
           Finance::RecordCashCount::MissingDifferenceAccount,
           Finance::RecordCashLine::MonthClosed, Date::Error => e
      @expected_cents = expected_for(@count.counted_on)
      flash.now[:alert] = e.message
      render :edit, status: :unprocessable_entity
    end

    private

    def record!(existing = nil)
      Finance::RecordCashCount.new(
        cash_account: @account, counted_on: counted_on,
        denominations: params.dig(:cash_count, :denominations)&.to_unsafe_h,
        comment: params.dig(:cash_count, :comment),
        resolution: params.dig(:cash_count, :resolution),
        counted_by: current_user, count: existing, whodunnit: current_user&.email
      ).run!
    end

    # Un brouillon renvoie à la feuille du mois compté : on y va pour saisir la
    # ligne qui manque, c'est le geste suivant et il ne doit pas se chercher.
    def after_record(count)
      if count.draft?
        redirect_to finance_cash_sheet_path(month: count.counted_on.strftime("%Y-%m"),
                                            cash_account_id: @account&.id),
                    notice: "Comptage gardé en brouillon — #{signed(count.difference_cents)} à retrouver. " \
                            "Saisis la ligne manquante, puis reprends le comptage."
      elsif count.balanced?
        redirect_to finance_cash_counts_path, notice: "Caisse juste au centime. C'est noté."
      else
        redirect_to finance_cash_counts_path,
                    notice: "Écart de #{signed(count.difference_cents)} assumé et écrit " \
                            "sur le compte des écarts de caisse."
      end
    end

    def signed(cents)
      "#{cents.negative? ? '−' : '+'}#{helpers.number_to_currency(cents.abs / 100.0)}"
    end

    def counted_on
      raw = params.dig(:cash_count, :counted_on)
      raw.present? ? Date.parse(raw) : Date.current
    end

    def expected_for(date)
      return 0 if @account.blank?

      Finance::CashSheet.accounting_balance(cash_account: @account, up_to: date)
    end

    # La caisse ACTIVE, comme la feuille : jamais un nom en dur.
    def get_account
      scope = CashAccount.actives.where(kind: "cash").ordered
      @account = scope.find_by(id: params[:cash_account_id]) || scope.first
    end

    def get_count
      @count = CashCount.find(params[:id])
      return unless @count.validated?

      redirect_to finance_cash_counts_path, alert: "Un comptage validé ne se modifie plus — refais-en un."
    end

    def accounting_secondary = "cash_sheet"
  end
end
