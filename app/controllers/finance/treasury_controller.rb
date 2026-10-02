module Finance
  # La trésorerie de la Fondation, en détail : la courbe, les comptes, ce qui
  # doit rentrer, ce qui doit sortir, et les vieux restes dus à assainir. Le
  # résumé vit sur la page Comptabilité ; ici, chaque chiffre a sa liste.
  class TreasuryController < AccountingBaseController
    breadcrumb "Solde et prévisions", :finance_treasury_path, match: :exact

    def show
      @treasury = Finance::Treasury.for_foundation
    end

    private

    def accounting_secondary = "accounting"
  end
end
