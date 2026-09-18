module Finance
  # La file « À payer » (epic #240, phase 4).
  #
  # Une dette validée qui n'apparaît nulle part se paie en retard, ou deux fois.
  # Cet écran répond à UNE question, celle du mercredi matin devant Triodos :
  # qu'est-ce que je vire aujourd'hui, à qui, sur quel compte, avec quelle
  # communication.
  #
  # Il liste les factures d'achat `to_pay`, depuis l'epic #241 phase 3 les notes
  # de frais et de mission `processing` — celles dont la pièce est émise et dont
  # l'argent n'est pas encore sorti — et depuis l'epic #248 phase 3 les relevés
  # de dépôt-vente à virer, et depuis l'epic #245 phase 3 les parts
  # d'organisateurs d'événements réglés. Les dettes restantes (relevés de
  # porteurs) se brancheront ICI de la même façon, dans `rows`, sans toucher à
  # la vue : c'est tout l'intérêt du contrat `Payable`.
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
      (invoices + expense_reports + consignment_reports + event_settlement_lines)
        .sort_by { |row| [row.payable_due_on || Date.new(9999, 1, 1), row.class.name, row.id] }
    end

    # Les parts d'organisateurs d'événements réglés (epic #245, phase 3). Un
    # règlement passe `paid` quand toutes ses parts sont soldées : ici on ne
    # garde donc que ce qui n'a pas encore été viré.
    def event_settlement_lines
      EventSettlementLine.joins(:event_settlement)
                         .where(event_settlements: { status: "issued" })
                         .includes(:human, :cash_allocations, event_settlement: :event)
                         .to_a
                         .reject(&:payable_settled?)
    end

    def invoices
      PurchaseInvoice.payable
                     .includes(:third_party, :legal_entity, :cash_allocations)
                     .to_a
    end

    # Les relevés de dépôt-vente en mode VIREMENT, vérifiés et comptabilisés
    # (epic #248, phase 3). Ceux dont l'artisan facture n'y sont pas : leur dette
    # est portée par la facture d'achat, déjà listée plus haut — les compter deux
    # fois gonflerait le total à payer d'autant.
    def consignment_reports
      ConsignmentReport.awaiting_settlement
                       .includes(:consignor, :legal_entity, :cash_allocations)
                       .to_a
                       .select(&:awaiting_transfer?)
                       .reject(&:payable_settled?)
    end

    # `processing` = la pièce est émise, l'argent n'est pas sorti. Une note
    # `recorded` n'a pas encore d'écriture : la payer n'aurait rien à solder.
    #
    # Les notes déjà soldées sont écartées ici et non par un statut : le passage
    # en `paid` est un `after_commit` du rapprochement, et une note couverte mais
    # pas encore rafraîchie n'a rien à faire dans la file du mercredi matin.
    def expense_reports
      ExpenseReport.to_pay
                   .includes(:human, :legal_entity, :expense_lines, :cash_allocations)
                   .to_a
                   .reject(&:payable_settled?)
    end

    def accounting_secondary = "payables"
  end
end
