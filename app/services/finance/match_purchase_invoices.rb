module Finance
  # Le rapprochement d'une ligne bancaire sortante avec une facture d'achat qui
  # attend son virement (epic #240, phase 4).
  #
  # **Ce service ne crée AUCUNE allocation** (invariant B4, comme
  # `SuggestAllocations`) : il propose, il motive, un humain clique. Une machine
  # qui affecte seule finit par affecter mal, et personne ne le voit avant
  # l'arrêté.
  #
  # Trois indices, dans cet ordre de confiance. La communication structurée de
  # la facture citée sur la ligne (2026-11-05). L'IBAN de la contrepartie désigne
  # un compte, pas une coïncidence — mais il est chiffré au repos, la
  # comparaison se fait donc en mémoire, sur les seules factures `to_pay`, qui
  # se comptent en dizaines. Le montant exact reste une présomption : deux
  # fournisseurs peuvent facturer la même somme le même mois.
  #
  # Calqué sur `Finance::MatchMemberPayouts` : même forme, même écran, même
  # geste — l'équipe n'a pas à apprendre deux vocabulaires pour le même travail.
  #
  # Dans l'autre sens (2026-11-01) : une ligne ENTRANTE peut être le
  # remboursement d'une note de crédit « À rembourser », mêmes indices.
  class MatchPurchaseInvoices
    Match = Struct.new(:invoice, :third_party, :due_cents, :reason, :confidence, keyword_init: true)

    COMMUNICATION_CONFIDENCE = 99
    IBAN_CONFIDENCE   = 95
    # Une facture déclarée réglée par la banque (2026-11-12) attend SA ligne :
    # le même montant autour de la date du règlement vaut presque l'IBAN.
    SETTLED_CONFIDENCE = 90
    AMOUNT_CONFIDENCE = 70

    def initialize(invoices: nil)
      @invoices = invoices
    end

    def for_entry(entry)
      return [] if entry.amount_cents.zero?
      return [] if entry.cash_allocations.any?

      montant = entry.amount_cents.abs
      iban = normalized(entry.counterparty_iban)
      candidates = invoices.select { |invoice| invoice.credit_note? == entry.amount_cents.positive? }

      candidates.filter_map do |invoice|
        du = invoice.remaining_cents
        next unless du.positive?

        if cites_communication?(entry, invoice)
          Match.new(invoice: invoice, third_party: invoice.third_party, due_cents: du,
                    reason: "La ligne cite la communication #{invoice.payment_reference}",
                    confidence: COMMUNICATION_CONFIDENCE)
        elsif iban.present? && normalized(invoice.payable_iban) == iban
          Match.new(invoice: invoice, third_party: invoice.third_party, due_cents: du,
                    reason: "L'IBAN de la ligne est celui de #{invoice.third_party&.name}",
                    confidence: IBAN_CONFIDENCE)
        elsif du == montant && settled_around?(invoice, entry)
          Match.new(invoice: invoice, third_party: invoice.third_party, due_cents: du,
                    reason: "#{invoice.payable_label} est déclarée réglée par la banque le " \
                            "#{I18n.l(invoice.settled_on, format: :short)}, pour ce montant",
                    confidence: SETTLED_CONFIDENCE)
        elsif du == montant
          Match.new(invoice: invoice, third_party: invoice.third_party, due_cents: du,
                    reason: "#{invoice.payable_label} #{invoice.credit_note? ? 'nous doit' : 'attend'} exactement ce montant",
                    confidence: AMOUNT_CONFIDENCE)
        end
      end.sort_by { |match| -match.confidence }
    end

    # Une passe sur toute une page : les factures `to_pay` sont chargées UNE
    # fois. Les recharger ligne à ligne est ce qui avait fait tomber l'écran
    # « À affecter » à l'issue #202.
    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def settled_around?(invoice, entry)
      return false unless invoice.settled_by_bank? && invoice.settled_on

      ((invoice.settled_on - PurchaseInvoices::BankLineCandidates::BEFORE)..
        (invoice.settled_on + PurchaseInvoices::BankLineCandidates::AFTER)).cover?(entry.entry_date)
    end

    def invoices
      @invoices ||= PurchaseInvoice.with_status("to_pay")
                                   .includes(:third_party, :legal_entity, :cash_allocations, :credited_invoice).to_a
    end

    # La communication structurée de la facture recopiée sur la ligne
    # (« 101 453708434944 ») : le fournisseur l'a demandée pour CETTE facture,
    # c'est l'indice le plus sûr (Michael, 2026-11-05).
    def cites_communication?(entry, invoice)
      digits = OrphanSupplierPayments.structured_digits(invoice.payment_reference)
      OrphanSupplierPayments.cites_reference?(entry.communication, digits) ||
        OrphanSupplierPayments.cites_reference?(entry.label, digits)
    end

    def normalized(iban) = iban.to_s.gsub(/\s+/, "").upcase.presence
  end
end
