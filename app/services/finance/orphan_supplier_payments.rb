module Finance
  # Le paiement d'une facture d'achat déjà passé au 440000, mais SANS la
  # facture (Michael, 2026-11-05, VOO) : une règle d'affectation (« Orange
  # Belgium - paiements » → 440000) a pris la domiciliation avant que la
  # facture soit encodée, ou sans la désigner. La dette est soldée au grand
  # livre, mais la facture reste « À payer » : on risque de la payer deux fois.
  #
  # Ce service PROPOSE, il n'écrit rien (invariant B4, comme
  # `MatchPurchaseInvoices`) : la fiche de la facture montre les candidates,
  # un humain clique « Relier » (`Finance::LinkOrphanPayment`).
  #
  # Une candidate : une affectation 440000 sans pièce, de la même entité, sans
  # tiers ou du tiers de la facture, dans le bon sens, du montant exact de ce
  # qui reste dû, datée au plus tôt quinze jours avant la facture. Les indices,
  # du plus sûr au plus faible : la communication structurée de la facture
  # citée sur la ligne, l'IBAN du fournisseur, le tiers déjà posé sur
  # l'affectation, le nom du fournisseur dans la contrepartie. Sans aucun
  # d'eux, le montant seul ne vaut que dans la fenêtre de l'échéance.
  class OrphanSupplierPayments
    Candidate = Struct.new(:allocation, :cash_entry, :reason, :confidence, keyword_init: true)

    SUPPLIER_CODE = "440000".freeze
    EARLIEST_BEFORE_ISSUE = 15.days
    AMOUNT_ONLY_AFTER_DUE = 30.days

    COMMUNICATION_CONFIDENCE = 99
    IBAN_CONFIDENCE = 95
    THIRD_PARTY_CONFIDENCE = 90
    NAME_CONFIDENCE = 80
    AMOUNT_CONFIDENCE = 60

    # Les chiffres d'une communication structurée, tels qu'une banque les
    # recopie (« 101 453708434944 », « +++453/7084/34944+++ ») : on compare les
    # douze chiffres, pas la mise en forme.
    def self.structured_digits(reference)
      return nil if reference.blank?

      MailIntake::StructuredCommunication.normalize(reference)&.gsub(/\D/, "")
    end

    # Les chiffres doivent tenir dans UNE suite de chiffres de la ligne, ou
    # dans une communication structurée qu'elle cite : coller toutes les suites
    # ensemble ferait naître des douzaines à cheval sur deux nombres.
    def self.cites_reference?(text, digits)
      return false if digits.blank? || text.blank?

      text.to_s.scan(/\d+/).any? { |run| run.include?(digits) } ||
        MailIntake::StructuredCommunication.scan(text).any? { |ref| ref.gsub(/\D/, "") == digits }
    end

    def initialize(invoices:)
      @invoices = Array(invoices).select { |invoice| invoice.to_pay? && !invoice.credit_note? }
    end

    # { invoice_id => [Candidate, …] }, du plus sûr au plus faible. Les
    # affectations orphelines sont chargées UNE fois pour toute la file.
    def by_invoice
      @by_invoice ||= @invoices.each_with_object({}) do |invoice, hash|
        candidates = candidates_for(invoice)
        hash[invoice.id] = candidates if candidates.any?
      end
    end

    def for(invoice) = by_invoice.fetch(invoice.id, [])

    private

    def candidates_for(invoice)
      du = invoice.remaining_cents
      return [] unless du.positive?

      digits = self.class.structured_digits(invoice.payment_reference)
      iban = normalized(invoice.payable_iban)

      orphans.fetch(du, []).filter_map do |allocation|
        next unless allocation.legal_entity_id == invoice.legal_entity_id
        next if allocation.third_party_id.present? && allocation.third_party_id != invoice.third_party_id

        entry = allocation.cash_entry
        next if entry.entry_date < invoice.issued_on - EARLIEST_BEFORE_ISSUE

        reason, confidence = hint(invoice, entry, allocation, digits, iban)
        next if reason.nil?

        Candidate.new(allocation: allocation, cash_entry: entry, reason: reason, confidence: confidence)
      end.sort_by { |candidate| [-candidate.confidence, candidate.cash_entry.entry_date] }
    end

    def hint(invoice, entry, allocation, digits, iban)
      if self.class.cites_reference?(entry.communication, digits) || self.class.cites_reference?(entry.label, digits)
        ["La ligne cite la communication #{invoice.payment_reference}", COMMUNICATION_CONFIDENCE]
      elsif iban.present? && normalized(entry.counterparty_iban) == iban
        ["L'IBAN de la ligne est celui de #{invoice.third_party&.name}", IBAN_CONFIDENCE]
      elsif allocation.third_party_id.present?
        ["L'affectation est déjà au nom de #{invoice.third_party&.name}", THIRD_PARTY_CONFIDENCE]
      elsif names_match?(entry.counterparty_name, invoice.third_party&.name)
        ["La contrepartie « #{entry.counterparty_name} » est #{invoice.third_party&.name}", NAME_CONFIDENCE]
      elsif within_due_window?(invoice, entry)
        ["Même montant, payé autour de l'échéance", AMOUNT_CONFIDENCE]
      end
    end

    def within_due_window?(invoice, entry)
      fin = (invoice.due_on || invoice.issued_on) + AMOUNT_ONLY_AFTER_DUE
      entry.entry_date <= fin
    end

    # Les affectations 440000 sans pièce, groupées par montant absolu. Une
    # facture se paie depuis une ligne SORTANTE : on ne garde que celles-là.
    def orphans
      @orphans ||= begin
        montants = @invoices.map(&:remaining_cents).select(&:positive?).uniq
        if montants.empty?
          {}
        else
          CashAllocation.joins(:general_account, :cash_entry)
                        .where(general_accounts: { code: SUPPLIER_CODE }, document_id: nil)
                        .where(amount_cents: montants.map(&:-@))
                        .where(cash_entries: { deleted_at: nil }).where.not(cash_entries: { status: "excluded" })
                        .includes(:cash_entry)
                        .group_by { |allocation| allocation.amount_cents.abs }
        end
      end
    end

    def names_match?(counterparty, supplier)
      a = simplify(counterparty)
      b = simplify(supplier)
      return false if a.blank? || b.blank? || b.length < 3

      a.include?(b) || b.include?(a)
    end

    def simplify(text) = I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish.presence

    def normalized(iban) = iban.to_s.gsub(/\s+/, "").upcase.presence
  end
end
