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
      queue = Finance::PayableQueue.new
      @rows = queue.rows
      @total_cents = @rows.sum(&:payable_amount_cents)
      @overdue = @rows.select(&:payable_overdue?)
      @without_iban = @rows.reject(&:payable_ready?)
      @expected = queue.expected_payments
    end

    private

    def accounting_secondary = "payables"
  end
end
