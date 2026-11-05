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
      load_sepa
    end

    # Le fichier de virements SEPA des dettes cochées (Michael, 2026-11-05),
    # pour l'import de la banque en ligne. Il NE PAIE RIEN : les dettes restent
    # dans la file jusqu'à ce que le relevé ramène les virements et qu'on les
    # rapproche — un lot peut ne jamais être autorisé dans la banque.
    def sepa
      load_entity_filter
      return redirect_to(finance_payables_path, alert: "Choisis d'abord une structure : un fichier par structure.") unless @entity

      file = Finance::SepaCreditTransfer.new(
        legal_entity: @entity,
        debtor_account: Finance::SepaCreditTransfer.debtor_accounts(@entity).find { |a| a.id == params[:cash_account_id].to_i },
        payables: selected_payables,
        execution_date: execution_date
      )
      send_data file.to_xml, filename: file.filename, type: "application/xml", disposition: "attachment"
    rescue Finance::SepaCreditTransfer::Error => e
      redirect_to finance_payables_path(legal_entity_id: @entity.id), alert: e.message
    end

    private

    # Une clé par dette, « Classe:id » : la file mélange factures, notes de
    # frais, relevés… dont les ids se recoupent.
    helper_method def sepa_key(row) = "#{row.class.name}:#{row.id}"

    def load_sepa
      return unless @entity

      @sepa_accounts = Finance::SepaCreditTransfer.debtor_accounts(@entity)
      @sepa_problems = @rows.to_h { |row| [sepa_key(row), Finance::SepaCreditTransfer.problem_for(row)] }
    end

    # Relues dans la file de la structure, jamais d'après le formulaire : une
    # dette soldée entre-temps, ou d'une autre structure, n'y est plus.
    def selected_payables
      keys = Array(params[:payables]).map(&:to_s)
      Finance::PayableQueue.new(legal_entity: @entity).rows.select { |row| keys.include?(sepa_key(row)) }
    end

    def execution_date
      Date.iso8601(params[:execution_date].to_s)
    rescue Date::Error
      Date.current
    end

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
