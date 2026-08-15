module Finance
  # L'arrêté du mois — l'écran qui dit ce qui reste à faire.
  #
  # Un seul endroit à ouvrir le 5 du mois pour savoir si le mois précédent est
  # fini. Rien n'y est stocké : tout se recalcule, donc rien n'y ment.
  class MonthlyCloseController < Finance::BaseController
    breadcrumb "Comptabilité", :finance_accounting_path, match: :exact
    breadcrumb "Arrêté du mois", :finance_monthly_close_path, match: :exact

    def show
      @month = parsed_month
      @steps = Finance::MonthlyClose.call(month: @month)
      @blocking = @steps.select(&:blocking?).reject { |step| step.key == :closing }
      @closing = MonthClosing.find_by(period_month: @month)
      @closings = MonthClosing.ordered.limit(6)
    end

    # On ne peut arrêter un mois que si tout ce qui bloque est levé. Le bouton
    # n'est pas grisé « par prudence » : il refuse, et il dit pourquoi.
    def close
      @month = parsed_month
      steps = Finance::MonthlyClose.call(month: @month)
      bloquantes = steps.select(&:blocking?).reject { |step| step.key == :closing }

      if bloquantes.any?
        return redirect_to finance_monthly_close_path(month: @month.strftime("%Y-%m")),
                           alert: "Il reste #{bloquantes.size} point(s) à traiter : " \
                                  "#{bloquantes.map(&:title).join(' · ')}."
      end

      MonthClosing.create!(period_month: @month, closed_at: Time.current,
                           closed_by: current_user&.email, notes: params[:notes])

      redirect_to finance_monthly_close_path(month: @month.strftime("%Y-%m")),
                  notice: "#{I18n.l(@month, format: '%B %Y').capitalize} est arrêté."
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Deux clics simultanés : l'index unique tranche, et on rend un message
      # plutôt qu'une 500. Le mois est arrêté dans les deux cas.
      message = MonthClosing.closed?(@month) ? "Ce mois était déjà arrêté." : e.message
      redirect_to finance_monthly_close_path(month: @month.strftime("%Y-%m")), alert: message
    end

    def reopen
      @month = parsed_month
      MonthClosing.find_by(period_month: @month)&.destroy

      redirect_to finance_monthly_close_path(month: @month.strftime("%Y-%m")),
                  notice: "Le mois est rouvert."
    end

    private

    def finance_secondary = "accounting"

    def parsed_month
      raw = params[:month].presence
      (raw ? Date.parse("#{raw}-01") : Date.current.prev_month).beginning_of_month
    rescue Date::Error
      Date.current.prev_month.beginning_of_month
    end
  end
end
