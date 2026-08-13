module Finance
  # Décomptes mensuels — émission, envoi, relances (issue #160).
  #
  # Tout est explicite : aucune émission, aucun envoi, aucune relance ne part
  # d'un job de fond. L'ActiveJob de l'app est en adaptateur `async` (un job
  # posé en file disparaît au redémarrage) et, sur un sujet aussi social qu'une
  # dette entre voisins, un automatisme silencieux serait de toute façon une
  # mauvaise idée.
  class StatementsController < Finance::BaseController
    before_action :get_statement, only: [:send_email, :remind, :mark_settled]

    breadcrumb "Décomptes", :finance_statements_path, match: :exact

    def index
      @month = parsed_month
      @statements = AccountStatement.for_month(@month).includes(:member_account).to_a
      issued_ids = @statements.map(&:member_account_id)

      # Sélection par défaut : les comptes au solde NON NUL. Envoyer « tu dois
      # 0,00 € » à quinze personnes chaque mois est le meilleur moyen de faire
      # ignorer le décompte de celui qui doit vraiment quelque chose.
      @candidates = MemberAccount.ordered.where(active: true).reject { |a| issued_ids.include?(a.id) }
      @include_zero = params[:include_zero] == "1"
      @candidates = @candidates.reject { |a| a.balance_cents.zero? } unless @include_zero
    end

    def issue
      @month = parsed_month
      issued = []
      refused = []

      Array(params[:member_account_ids]).each do |id|
        account = MemberAccount.find(id)
        begin
          issued << Finance::IssueStatement.new(member_account: account, month: @month,
                                                whodunnit: current_user&.email).run!
        rescue Finance::IssueStatement::RecurringChargesMissing, Finance::IssueStatement::AlreadyIssued => e
          refused << "#{account.name} : #{e.message}"
        end
      end

      notice = "#{issued.compact.size} décompte(s) émis."
      flash[:alert] = refused.join(" · ") if refused.any?
      redirect_to finance_statements_path(month: @month.strftime("%Y-%m")), notice: notice
    end

    def send_email
      if recipient_missing?
        return redirect_back fallback_location: finance_statements_path,
                             alert: "Ce compte n'a pas d'email de contact — ajoute-le sur la fiche."
      end

      FinanceStatementMailer.statement(@statement).deliver_now
      @statement.update!(status: "sent", sent_at: Time.current)

      redirect_back fallback_location: finance_statements_path,
                    notice: "Décompte envoyé à #{@statement.member_account.name}."
    end

    def remind
      if recipient_missing?
        return redirect_back fallback_location: finance_statements_path,
                             alert: "Ce compte n'a pas d'email de contact."
      end

      FinanceStatementMailer.reminder(@statement).deliver_now
      @statement.update!(reminders_count: @statement.reminders_count + 1, last_reminder_at: Time.current)

      redirect_back fallback_location: finance_statements_path,
                    notice: "Relance envoyée (#{@statement.reminders_count}e)."
    end

    def mark_settled
      @statement.update!(status: "settled")
      redirect_back fallback_location: finance_statements_path, notice: "Décompte marqué réglé."
    end

    private

    def get_statement
      @statement = AccountStatement.find(params[:id])
    end

    def recipient_missing?
      account = @statement.member_account
      account.contact_email.blank? && account.human&.email.blank?
    end

    def parsed_month
      raw = params[:month].presence
      raw ? Date.parse("#{raw}-01") : Date.current.beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    def finance_secondary = "statements"
  end
end
