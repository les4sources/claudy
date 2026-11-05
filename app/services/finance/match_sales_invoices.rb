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
  # Trois indices. La communication d'abord : la communication structurée de
  # la facture (« +++123/4567/89012+++ », reprise d'OkiOki) ou son NUMÉRO
  # (« 2026-047 ») — c'est le client qui désigne la facture (Michael, 2026-10-30). Le montant
  # exact ensuite — ce qui reste dû, pour la seconde moitié d'une facture
  # payée en deux fois. L'IBAN enfin : celui que `customer_bank_accounts` a
  # appris à la ventilation d'un séjour, ou celui du tiers de la facture.
  class MatchSalesInvoices
    Match = Struct.new(:invoice, :reason, :confidence, keyword_init: true)

    CONFIDENCE_NUMBER = 95
    CONFIDENCE_AMOUNT = 80
    CONFIDENCE_IBAN = 70

    def initialize(invoices: nil)
      @invoices = invoices
    end

    # Une ligne déjà entamée se rapproche encore : un virement solde parfois
    # deux factures, l'une après l'autre.
    def for_entry(entry)
      return [] unless entry.amount_cents.positive?
      return [] unless entry.remaining_cents.positive?

      clients = customers_for(entry)
      texte = [entry.communication, entry.label].compact.join(" ")

      candidates.filter_map { |invoice| match_for(entry, invoice, clients, texte) }
                .sort_by { |match| [-match.confidence, match.invoice.number.to_s] }
    end

    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def match_for(entry, invoice, clients, texte)
      du = remaining_for(invoice)
      if self.class.reference_cited?(texte, invoice.payment_reference)
        Match.new(invoice: invoice, confidence: CONFIDENCE_NUMBER,
                  reason: "La communication structurée est celle de la facture #{invoice.number}")
      elsif numero_cite?(texte, invoice.number)
        Match.new(invoice: invoice, confidence: CONFIDENCE_NUMBER,
                  reason: "La communication cite la facture #{invoice.number}")
      elsif du == entry.remaining_cents
        Match.new(invoice: invoice, confidence: CONFIDENCE_AMOUNT,
                  reason: du == invoice.total_cents ? "Le montant de la facture #{invoice.number} correspond exactement" :
                                                      "Le reste dû de la facture #{invoice.number} correspond exactement")
      elsif invoice.customer_id.present? && clients.include?(invoice.customer_id)
        Match.new(invoice: invoice, confidence: CONFIDENCE_IBAN,
                  reason: "Cet IBAN est celui d'un paiement déjà reçu de ce client")
      elsif entry.counterparty_iban.present? && invoice.third_party&.iban == entry.counterparty_iban
        Match.new(invoice: invoice, confidence: CONFIDENCE_IBAN,
                  reason: "Cet IBAN est celui de #{invoice.third_party.name}")
      end
    end

    # Calculé une fois par facture pour toute la page : la file compare chaque
    # ligne à chaque facture émise.
    def remaining_for(invoice)
      @remaining ||= {}
      @remaining[invoice.id] ||= invoice.remaining_cents
    end

    # Le numéro entier, pas un morceau d'un autre : « 2026-04 » ne doit pas se
    # lire dans « 2026-047 », ni « 047 » dans un montant.
    def numero_cite?(texte, numero) = self.class.cites?(texte, numero)

    # La communication structurée belge : ses 12 chiffres, où qu'ils soient
    # dans la communication, avec ou sans « +++ », barres ou espaces.
    def self.reference_cited?(texte, reference)
      chiffres = reference.to_s.gsub(/\D/, "")
      return false if texte.blank? || chiffres.length < 10

      texte.gsub(/\D/, "").include?(chiffres)
    end

    def self.cites?(texte, numero)
      return false if texte.blank? || numero.to_s.length < 4

      texte.match?(/(?<![\w-])#{Regexp.escape(numero)}(?![\w-])/i)
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
    # l'encaisser deux fois. Une note de crédit ne s'encaisse pas.
    def candidates
      @candidates ||= (@invoices || SalesInvoice.invoices.issued.includes(:customer, :third_party, :legal_entity).ordered).to_a
    end
  end
end
