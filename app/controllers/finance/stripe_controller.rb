module Finance
  # Comptabilité > Stripe (epic #250, phase 2).
  #
  # Ce que l'écran répond : où en est chaque compte Stripe, et où va chaque
  # catégorie de ventes. Jusqu'ici le mode d'un compte se changeait en console,
  # et les correspondances par catégorie se créaient au rake — ce qui revenait à
  # demander un accès serveur pour une décision de gestion. La lecture et le
  # changement de mode vivent dans `Finance::StripeAccounts`, que le connecteur
  # Claude appelle aussi.
  class StripeController < AccountingBaseController
    breadcrumb "Stripe", :finance_stripe_path, match: :exact

    def index
      @accounts = Finance::StripeAccounts.new.blocks
    end

    def update_mode
      account = CashAccount.stripe.find(params[:id])
      Finance::StripeAccounts.new.change_mode!(account, params[:stripe_mode])
      redirect_to finance_stripe_path, notice: "#{account.name} : #{account.stripe_mode_label}."
    rescue Finance::StripeAccounts::ModeRefused, ActiveRecord::RecordInvalid => e
      redirect_to finance_stripe_path, alert: e.message
    end

    private

    def accounting_secondary = "stripe"
  end
end
