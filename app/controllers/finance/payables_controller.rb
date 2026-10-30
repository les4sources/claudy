module Finance
  # La file « À payer » (epic #240, phase 4).
  #
  # Une dette validée qui n'apparaît nulle part se paie en retard, ou deux fois.
  # Cet écran répond à UNE question, celle du mercredi matin devant Triodos :
  # qu'est-ce que je vire aujourd'hui, à qui, sur quel compte, avec quelle
  # communication.
  #
  # La file elle-même vit dans `Finance::PayableQueue`, que la trésorerie lit
  # aussi : une seule liste de dettes pour les deux écrans.
  class PayablesController < AccountingBaseController
    breadcrumb "À payer", :finance_payables_path, match: :exact

    def index
      load_entity_filter
      queue = Finance::PayableQueue.new(legal_entity: @entity)
      @rows = queue.rows
      @total_cents = @rows.sum(&:payable_amount_cents)
      @overdue = @rows.select(&:payable_overdue?)
      @without_iban = @rows.reject(&:payable_ready?)
      @expected = queue.expected_payments
      @not_ready = not_ready_invoices
    end

    private

    # Les factures reçues qui ne sont pas encore « à payer » (à traiter, à
    # valider), Michael 2026-10-30 : hors file et hors total — sans
    # ventilation ni validation il n'y a pas d'écriture — mais visibles ici,
    # parce que leur échéance court quand même.
    def not_ready_invoices
      scope = PurchaseInvoice.where(status: %w[to_process to_validate]).includes(:third_party, :legal_entity)
      scope = scope.where(legal_entity_id: @entity.id) if @entity
      scope.to_a.sort_by { |invoice| [invoice.due_on || Date.new(9999, 1, 1), invoice.id] }
    end

    def accounting_secondary = "payables"
  end
end
