module Finance
  # Le rapprochement d'une ligne bancaire ENTRANTE avec une facture de vente
  # (epic #240, phase 6).
  #
  # Une facture OkiOki part chez le client, l'argent arrive sur le Triodos, et
  # rien ne relie les deux : la facture reste « émise » indéfiniment, même
  # payée. Ce service propose le lien.
  #
  # **Il ne crée RIEN** (invariant B4) : il propose, il motive, un humain
  # clique. Même patron que `MatchPurchaseInvoices` et `MatchStripePayouts`.
  #
  # Deux indices. Le montant exact d'abord — une facture de vente est payée en
  # une fois, à l'euro près, bien plus souvent qu'une facture d'achat. L'IBAN
  # APPRIS ensuite : `customer_bank_accounts` mémorise, à chaque ventilation de
  # séjour, le compte depuis lequel un client a payé. Le deuxième virement du
  # même client se reconnaît donc tout seul.
  class MatchSalesInvoices
    Match = Struct.new(:invoice, :reason, :confidence, keyword_init: true)

    CONFIDENCE_AMOUNT = 80
    CONFIDENCE_IBAN = 70

    def initialize(invoices: nil)
      @invoices = invoices
    end

    def for_entry(entry)
      return [] unless entry.amount_cents.positive?
      return [] if entry.cash_allocations.any?

      clients = customers_for(entry)

      candidates.filter_map { |invoice| match_for(entry, invoice, clients) }
                .sort_by { |match| [-match.confidence, match.invoice.number.to_s] }
    end

    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def match_for(entry, invoice, clients)
      if invoice.total_cents == entry.amount_cents
        Match.new(invoice: invoice, confidence: CONFIDENCE_AMOUNT,
                  reason: "Le montant de la facture #{invoice.number} correspond exactement")
      elsif invoice.customer_id.present? && clients.include?(invoice.customer_id)
        Match.new(invoice: invoice, confidence: CONFIDENCE_IBAN,
                  reason: "Cet IBAN est celui d'un paiement déjà reçu de ce client")
      end
    end

    # Les clients connus pour l'IBAN de la ligne. Un compte joint peut en
    # désigner plusieurs : `CustomerBankAccount.customers_for` les rend tous
    # plutôt que d'en choisir un au hasard.
    def customers_for(entry)
      return [] if entry.counterparty_iban.blank?

      @customers_by_iban ||= {}
      @customers_by_iban[entry.counterparty_iban] ||=
        CustomerBankAccount.customers_for(entry.counterparty_iban).map(&:id)
    end

    # Les factures ÉMISES, chargées une fois pour la page. Une facture déjà
    # payée ne se propose plus : la proposer une seconde fois, c'est inviter à
    # l'encaisser deux fois.
    def candidates
      @candidates ||= (@invoices || SalesInvoice.issued.includes(:customer, :legal_entity).ordered).to_a
    end
  end
end
