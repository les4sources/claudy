module Finance
  # Le contrôle croisé (issue #183) : les recettes affectées au journal en
  # regard du chiffre d'affaires des séjours.
  #
  # L'écart n'est PAS une anomalie, et l'écran le dit. Le journal mesure
  # l'argent encaissé et ventilé ; les séjours mesurent ce qui a été facturé.
  # L'écart, c'est ce qui reste à encaisser plus ce qui reste à affecter — deux
  # nombres qu'on affiche plutôt que de laisser croire à une erreur.
  #
  # Les montants des séjours sont LUS, jamais recalculés : `total_amount_cents`
  # est persisté au moment de la vente. Re-coter un vieux séjour donnerait un
  # montant qui n'a jamais été facturé, parce que deux moteurs de prix ont
  # coexisté dans l'application.
  class CrossCheckController < Finance::AccountingBaseController
    breadcrumb "Contrôle croisé", :finance_cross_check_path, match: :exact

    def index
      @month = parsed_month
      @from = @month.beginning_of_month
      @to = @month.end_of_month

      @journal_rows = journal_revenue_by_team
      @journal_total_cents = @journal_rows.sum { |row| row[:revenue_cents] }

      @stays = Stay.where(departure_date: @from..@to)
      @stays_total_cents = @stays.sum(:total_amount_cents)

      @cashed_cents = Payment.where(created_at: @from.beginning_of_day..@to.end_of_day)
                             .where(status: "paid").sum(:amount_cents)

      # Le reste à affecter DU MOIS : rapporter tout l'arriéré à l'écart d'un
      # mois donné ferait accuser ce mois-là d'un retard qui n'est pas le sien.
      pending = CashEntry.pending.in_period(@from, @to)
      @pending_entries = pending.count
      @pending_cents = pending.sum(:amount_cents)
      @pending_all_count = CashEntry.pending.count
      @delta_cents = @stays_total_cents - @journal_total_cents
    end

    private

    def journal_revenue_by_team
      lignes = JournalLine.joins(:journal_entry, :general_account)
                          .where(journal_entries: { entry_date: @from..@to })
                          .where(general_accounts: { klass: 7 })
                          .group(:team_id)
                          .pluck(Arel.sql("team_id, SUM(credit_cents), SUM(debit_cents)"))

      teams = Team.where(id: lignes.map(&:first).compact).index_by(&:id)
      lignes.map do |team_id, credits, debits|
        { team: teams[team_id], revenue_cents: credits.to_i - debits.to_i }
      end.sort_by { |row| row[:team]&.name || "zzz" }
    end

    def parsed_month
      raw = params[:month].presence
      raw ? Date.parse("#{raw}-01") : Date.current.beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end
  end
end
