module Finance
  # Dépôt et retrait du justificatif mensuel des frais Stripe (epic #240,
  # phase 5). Il n'y a ni validation, ni statut, ni paiement : ce document ne
  # produit aucune écriture, les frais sont déjà comptabilisés par la
  # ventilation des versements. On archive la pièce et on montre l'écart.
  class StripeFeeInvoicesController < Finance::AccountingBaseController
    def create
      @invoice = StripeFeeInvoice.find_for(params[:account_key], month) ||
                 StripeFeeInvoice.new(account_key: params[:account_key], period_month: month)
      @invoice.assign_attributes(invoice_params)

      if @invoice.save
        redirect_to finance_collection_cost_path(anchor: "justificatifs"), notice: "Justificatif enregistré."
      else
        redirect_to finance_collection_cost_path(anchor: "justificatifs"),
                    alert: @invoice.errors.full_messages.to_sentence.presence || "Enregistrement impossible."
      end
    end

    def destroy
      invoice = StripeFeeInvoice.find(params[:id])
      invoice.soft_delete!(validate: false)
      redirect_to finance_collection_cost_path(anchor: "justificatifs"), notice: "Justificatif retiré."
    end

    private

    def month
      Date.parse(params[:period_month].to_s).beginning_of_month
    rescue Date::Error, TypeError
      Date.current.beginning_of_month
    end

    def invoice_params
      # Le montant se saisit en EUROS (`declared_fee`, via `monetize`) : demander
      # des centimes à la personne qui tient la compta, c'est demander une
      # conversion de tête devant un PDF qui affiche des euros.
      params.require(:stripe_fee_invoice).permit(:declared_fee, :reference, :notes, :document)
    end
  end
end
