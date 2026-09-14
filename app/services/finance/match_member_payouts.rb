module Finance
  # Le rapprochement d'une ligne bancaire sortante avec un compte de membre
  # créditeur (epic #246, phase 2).
  #
  # Deux indices, dans cet ordre : l'IBAN de la contrepartie, puis le montant
  # exact. L'IBAN est le plus sûr — il désigne un compte, pas une coïncidence —
  # mais il est chiffré au repos, donc la comparaison se fait en mémoire, sur
  # les quelques comptes créditeurs. Le montant seul reste une proposition, pas
  # une certitude : c'est un humain qui accepte.
  class MatchMemberPayouts
    Match = Struct.new(:member_account, :human, :due_cents, :reason, :confidence, keyword_init: true)

    def initialize(payables: nil)
      @payables = payables || MemberPayables.new
    end

    # Les propositions pour une ligne de trésorerie, de la plus sûre à la moins.
    def for_entry(entry)
      return [] unless entry.amount_cents.negative?
      return [] if entry.cash_allocations.any?

      montant = entry.amount_cents.abs
      iban = normalized(entry.counterparty_iban)

      @payables.rows.filter_map do |row|
        if iban.present? && normalized(row.iban) == iban
          Match.new(member_account: row.member_account, human: row.human, due_cents: row.due_cents,
                    reason: "L'IBAN de la ligne est celui de #{row.iban_holder}", confidence: 95)
        elsif row.due_cents == montant
          Match.new(member_account: row.member_account, human: row.human, due_cents: row.due_cents,
                    reason: "#{row.member_account.name} attend exactement ce montant", confidence: 70)
        end
      end.sort_by { |match| -match.confidence }
    end

    # Une passe sur toute une page, sans refaire le calcul des soldes à chaque
    # ligne : c'est ce qui a fait tomber l'écran « À affecter » à l'issue #202.
    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def normalized(iban) = iban.to_s.gsub(/\s+/, "").upcase.presence
  end
end
