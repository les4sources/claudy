module Finance
  # La file « À payer » (epic #240, phase 4).
  #
  # Une dette validée qui n'apparaît nulle part se paie en retard, ou deux fois.
  # Cet écran répond à UNE question, celle du mercredi matin devant Triodos :
  # qu'est-ce que je vire aujourd'hui, à qui, sur quel compte, avec quelle
  # communication.
  #
  # Il ne liste pour l'instant que les factures d'achat `to_pay` — les autres
  # dettes (notes de frais, relevés de porteurs, parts d'événements, règlements
  # de dépôt-vente) répondent déjà au contrat `Payable` ou y répondront : elles
  # se brancheront ICI, dans `rows`, sans toucher à la vue.
  class PayablesController < AccountingBaseController
    breadcrumb "À payer", :finance_payables_path, match: :exact

    def index
      @rows = rows
      @total_cents = @rows.sum(&:payable_amount_cents)
      @overdue = @rows.select(&:payable_overdue?)
      @without_iban = @rows.reject(&:payable_ready?)
    end

    private

    # Triées par ÉCHÉANCE, les sans-échéance en dernier : c'est l'ordre dans
    # lequel on paie, pas l'ordre de saisie.
    def rows
      PurchaseInvoice.payable
                     .includes(:third_party, :legal_entity, :cash_allocations)
                     .to_a
                     .sort_by { |invoice| [invoice.payable_due_on || Date.new(9999, 1, 1), invoice.id] }
    end

    def accounting_secondary = "payables"
  end
end
