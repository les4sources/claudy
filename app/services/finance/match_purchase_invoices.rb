module Finance
  # Le rapprochement d'une ligne bancaire sortante avec une facture d'achat qui
  # attend son virement (epic #240, phase 4).
  #
  # **Ce service ne crée AUCUNE allocation** (invariant B4, comme
  # `SuggestAllocations`) : il propose, il motive, un humain clique. Une machine
  # qui affecte seule finit par affecter mal, et personne ne le voit avant
  # l'arrêté.
  #
  # Deux indices, dans cet ordre de confiance. L'IBAN de la contrepartie désigne
  # un compte, pas une coïncidence — mais il est chiffré au repos, la
  # comparaison se fait donc en mémoire, sur les seules factures `to_pay`, qui
  # se comptent en dizaines. Le montant exact reste une présomption : deux
  # fournisseurs peuvent facturer la même somme le même mois.
  #
  # Calqué sur `Finance::MatchMemberPayouts` : même forme, même écran, même
  # geste — l'équipe n'a pas à apprendre deux vocabulaires pour le même travail.
  class MatchPurchaseInvoices
    Match = Struct.new(:invoice, :third_party, :due_cents, :reason, :confidence, keyword_init: true)

    IBAN_CONFIDENCE   = 95
    AMOUNT_CONFIDENCE = 70

    def initialize(invoices: nil)
      @invoices = invoices
    end

    def for_entry(entry)
      return [] unless entry.amount_cents.negative?
      return [] if entry.cash_allocations.any?

      montant = entry.amount_cents.abs
      iban = normalized(entry.counterparty_iban)

      invoices.filter_map do |invoice|
        du = invoice.remaining_cents
        next unless du.positive?

        if iban.present? && normalized(invoice.payable_iban) == iban
          Match.new(invoice: invoice, third_party: invoice.third_party, due_cents: du,
                    reason: "L'IBAN de la ligne est celui de #{invoice.third_party&.name}",
                    confidence: IBAN_CONFIDENCE)
        elsif du == montant
          Match.new(invoice: invoice, third_party: invoice.third_party, due_cents: du,
                    reason: "#{invoice.payable_label} attend exactement ce montant",
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

    def invoices
      @invoices ||= PurchaseInvoice.payable.includes(:third_party, :legal_entity, :cash_allocations).to_a
    end

    def normalized(iban) = iban.to_s.gsub(/\s+/, "").upcase.presence
  end
end
