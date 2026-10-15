module Finance
  # Le rapprochement d'une ligne bancaire sortante avec un relevé de porteur
  # d'activité qui attend son virement (epic #244, phase 3).
  #
  # **Ce service ne crée AUCUNE allocation** (invariant B4, comme
  # `MatchExpenseReports`) : il propose, il motive, un humain clique.
  #
  # Trois indices, dans cet ordre de confiance : la référence du relevé
  # (ACT-12-202607) dans la communication, que le virement a recopiée ; l'IBAN
  # du tiers payé ; le montant exact, simple présomption. Un relevé réglé en
  # plusieurs virements (un porteur qui facture chaque atelier à part) ne se
  # devine pas : il se rapproche à la main, depuis la fiche de la ligne ou par
  # Claude (`rapprocher_ligne`, avec `releve_porteur`).
  class MatchCarrierStatements
    Match = Struct.new(:statement, :beneficiary, :due_cents, :reason, :confidence, keyword_init: true)

    REFERENCE_CONFIDENCE = 98
    IBAN_CONFIDENCE      = 95
    AMOUNT_CONFIDENCE    = 70

    def initialize(statements: nil)
      @statements = statements
    end

    def for_entry(entry)
      return [] unless entry.amount_cents.negative?
      return [] if entry.cash_allocations.any?

      montant = entry.amount_cents.abs
      iban = normalized(entry.counterparty_iban)
      texte = [entry.communication, entry.label].compact.join(" ").upcase

      statements.filter_map do |statement|
        du = statement.remaining_cents
        next unless du.positive?

        if texte.include?(statement.reference.upcase)
          match(statement, du, "La communication porte la référence #{statement.reference}", REFERENCE_CONFIDENCE)
        elsif iban.present? && normalized(iban_of(statement)) == iban
          match(statement, du, "L'IBAN de la ligne est celui de #{statement.payable_beneficiary}", IBAN_CONFIDENCE)
        elsif du == montant
          match(statement, du, "#{statement.payable_label} attend exactement ce montant", AMOUNT_CONFIDENCE)
        end
      end.sort_by { |m| -m.confidence }
    end

    # Une passe sur toute une page : les relevés émis sont chargés UNE fois.
    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def match(statement, du, reason, confidence)
      Match.new(statement: statement, beneficiary: statement.payable_beneficiary, due_cents: du,
                reason: reason, confidence: confidence)
    end

    def statements
      @statements ||= CarrierStatement.awaiting_payment
                                      .includes(:human, :third_party, :cash_allocations)
                                      .to_a
    end

    # Sans `payable_third_party`, qui CRÉE le tiers d'un porteur qui n'en a pas
    # encore : une proposition n'écrit rien.
    # Mémorisé : la page compte cinquante lignes, pas cinquante requêtes par relevé.
    def iban_of(statement)
      @ibans ||= {}
      return @ibans[statement.id] if @ibans.key?(statement.id)

      @ibans[statement.id] = (statement.third_party || ThirdParty.find_by(human_id: statement.human_id))&.iban
    end

    def normalized(iban) = iban.to_s.gsub(/\s+/, "").upcase.presence
  end
end
