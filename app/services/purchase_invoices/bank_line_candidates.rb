module PurchaseInvoices
  # Les lignes du relevé qui peuvent être le paiement d'une facture déclarée
  # « déjà réglée par la banque » (Michael, 2026-11-12) : sorties bancaires de
  # la même structure, encore à affecter, du montant qui reste dû, autour de la
  # date du règlement. La fiche les propose ; un humain clique (invariant B4 :
  # rien ne s'affecte tout seul).
  #
  # La ligne déjà affectée au 440000 sans la facture (une règle a pris la
  # domiciliation) n'est pas ici : `Finance::OrphanSupplierPayments` s'en charge.
  class BankLineCandidates
    # Une domiciliation peut précéder la facture ; un relevé arrive rarement
    # plus de deux mois après le paiement.
    BEFORE = 15.days
    AFTER = 60.days

    def initialize(invoice)
      @invoice = invoice
    end

    def entries
      return CashEntry.none unless @invoice.awaiting_bank_line?

      du = @invoice.remaining_cents
      return CashEntry.none unless du.positive?

      jour = @invoice.settled_on || @invoice.issued_on
      CashEntry.pending.outgoing
               .where(amount_cents: -du)
               .where(entry_date: (jour - BEFORE)..(jour + AFTER))
               .where(cash_account_id: CashAccount.where(kind: "bank", legal_entity_id: @invoice.legal_entity_id).select(:id))
               .where.not(id: CashAllocation.select(:cash_entry_id))
               .includes(:cash_account)
               .order(Arel.sql(CashEntry.sanitize_sql_array(["ABS(cash_entries.entry_date - ?::date)", jour])), :id)
               .limit(5)
    end
  end
end
