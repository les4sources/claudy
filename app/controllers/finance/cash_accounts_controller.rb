module Finance
  # Les comptes de trésorerie et leur IBAN (Michael, 2026-10-19). La page Import
  # CODA prévenait qu'un compte n'avait pas d'IBAN sans qu'aucun écran ne permît
  # de le poser : il fallait passer par le connecteur. Seul l'IBAN se corrige
  # ici — c'est lui qui relie un relevé à son compte. Une caisse ou un compte
  # Stripe ne reçoit pas de relevé bancaire : il n'a rien à saisir.
  class CashAccountsController < Finance::AccountingBaseController
    before_action :get_account, only: [:edit, :update]
    breadcrumb "Comptes de trésorerie", :finance_cash_accounts_path, match: :exact

    def index
      @accounts = CashAccount.ordered.includes(:legal_entity, :general_account)
    end

    def edit
      breadcrumb @account.name, edit_finance_cash_account_path(@account), match: :exact
    end

    def update
      @account.iban = CashAccount.format_iban(params.dig(:cash_account, :iban))

      if @account.save(context: :iban_entry)
        redirect_to finance_cash_accounts_path, notice: "IBAN de « #{@account.name} » enregistré."
      else
        breadcrumb @account.name, edit_finance_cash_account_path(@account), match: :exact
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def get_account = @account = CashAccount.where(kind: "bank").find(params[:id])
  end
end
