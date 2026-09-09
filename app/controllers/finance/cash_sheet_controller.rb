module Finance
  # Comptabilité > Caisse — la feuille du mois (epic #243, phase 2).
  #
  # C'est l'écran qui remplace la feuille papier : le mois, ses lignes, le solde
  # d'ouverture et le solde de clôture. La saisie se fait AU BAR, sur un
  # téléphone : le formulaire est en tête, la date se souvient d'une ligne à
  # l'autre, et un motif suffit à affecter la ligne.
  #
  # Le compte visé est la caisse ACTIVE, jamais un nom en dur : la production
  # tient sa caisse dans « Caisse du domaine », un seed en avait créé une
  # seconde, vide. Une feuille qui viserait un nom écrirait dans la mauvaise.
  class CashSheetController < Finance::AccountingBaseController
    before_action :get_account
    before_action :get_entry, only: %i[update exclude]

    breadcrumb "Caisse", :finance_cash_sheet_path, match: :exact

    def show
      @sheet = Finance::CashSheet.new(cash_account: @account, month: parsed_month) if @account
      @motifs = CashMotif.actives.ordered
      @accounts = CashAccount.actives.where(kind: "cash").ordered
      @last_date = params[:last_date].presence
    end

    def create
      motif = CashMotif.find_by(id: params.dig(:cash_line, :cash_motif_id))
      Finance::RecordCashLine.new(
        cash_account: @account, motif: motif,
        entry_date: params.dig(:cash_line, :entry_date),
        label: params.dig(:cash_line, :label),
        amount_cents: euros_to_cents(params.dig(:cash_line, :amount)),
        notes: params.dig(:cash_line, :notes),
        whodunnit: current_user&.email
      ).run!

      redraw(notice: "Ligne enregistrée.", month: parsed_month(params.dig(:cash_line, :entry_date)))
    rescue Finance::RecordCashLine::MissingMotif, Finance::RecordCashLine::MonthClosed,
           ArgumentError, Date::Error, ActiveRecord::RecordInvalid => e
      redraw(alert: e.message)
    end

    def update
      motif = CashMotif.find_by(id: params.dig(:cash_line, :cash_motif_id))
      Finance::UpdateCashLine.new(cash_entry: @entry, whodunnit: current_user&.email).update!(
        motif: motif || @entry.cash_motif,
        entry_date: params.dig(:cash_line, :entry_date),
        label: params.dig(:cash_line, :label),
        amount_cents: euros_to_cents(params.dig(:cash_line, :amount)),
        notes: params.dig(:cash_line, :notes)
      )

      redraw(notice: "Ligne corrigée.")
    rescue Finance::UpdateCashLine::MonthClosed, Accounting::UnpostCashEntry::ClosedFiscalYear,
           ArgumentError, Date::Error, ActiveRecord::RecordInvalid => e
      redraw(alert: e.message)
    end

    # « Supprimer » n'existe pas : une ligne s'exclut avec un motif (règle B2).
    def exclude
      Finance::UpdateCashLine.new(cash_entry: @entry, whodunnit: current_user&.email)
                             .exclude!(params[:reason])

      redraw(notice: "Ligne retirée de la feuille, avec son motif.")
    rescue Finance::UpdateCashLine::MonthClosed, Accounting::UnpostCashEntry::ClosedFiscalYear,
           ArgumentError, ActiveRecord::RecordInvalid => e
      redraw(alert: e.message)
    end

    private

    # Un seul rendu pour les trois gestes : le tableau, ses soldes et le
    # formulaire repartent ensemble. Recalculer les soldes courants ligne à
    # ligne dans un flux partiel coûterait plus cher que de redessiner la
    # feuille, qui tient en trente lignes.
    def redraw(month: nil, notice: nil, alert: nil)
      @sheet = Finance::CashSheet.new(cash_account: @account, month: month || parsed_month)
      @motifs = CashMotif.actives.ordered
      @accounts = CashAccount.actives.where(kind: "cash").ordered
      @last_date = params.dig(:cash_line, :entry_date).presence

      flash.now[:notice] = notice if notice
      flash.now[:alert] = alert if alert

      respond_to do |format|
        format.turbo_stream { render :redraw }
        format.html do
          flash[:notice] = notice if notice
          flash[:alert] = alert if alert
          redirect_to finance_cash_sheet_path(month: @sheet.month.strftime("%Y-%m"),
                                              cash_account_id: @account&.id,
                                              last_date: @last_date)
        end
      end
    end

    # La caisse ACTIVE (note de Michael, 2026-09-08) : `kind: cash`, active, et
    # celle qu'on demande explicitement si la maison en tient plusieurs.
    def get_account
      scope = CashAccount.actives.where(kind: "cash").ordered
      @account = scope.find_by(id: params[:cash_account_id]) || scope.first
    end

    def get_entry
      @entry = CashEntry.where(cash_account_id: @account&.id).find(params[:id])
    end

    def parsed_month(raw = params[:month])
      raw.present? ? Date.parse(raw.length == 7 ? "#{raw}-01" : raw).beginning_of_month : Date.current.beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    # Montant saisi en euros, virgule tolérée, signe ignoré : c'est le motif qui
    # décide du sens.
    def euros_to_cents(raw)
      (raw.to_s.tr(",", ".").to_f * 100).round.abs
    end

    def accounting_secondary = "cash_sheet"
  end
end
