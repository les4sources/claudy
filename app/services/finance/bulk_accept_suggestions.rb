module Finance
  # L'acceptation en masse, BORNÉE (issue #183) : une règle, ou un compte
  # proposé par Jev, au-dessus d'un seuil de confiance. Jamais « tout ».
  #
  # Une règle est une borne qu'un humain a écrite. Jev n'en a pas : sa borne
  # est donc le compte qu'il propose — « Jev → 701001 Bar à 95 % et plus » —,
  # pour qu'on accepte un lot dont on a vu la nature, jamais un mélange.
  #
  # Chaque suggestion passe par `AcceptSuggestion`, une à une, chacune dans sa
  # transaction : une ligne comptabilisée entre-temps est sautée, elle ne fait
  # pas échouer les autres.
  class BulkAcceptSuggestions
    SKIPPED = [AcceptSuggestion::AlreadyDecided, AcceptSuggestion::EntryPosted,
               Accounting::PostDocument::MissingFiscalYear].freeze

    Result = Struct.new(:accepted, :skipped, keyword_init: true)

    attr_reader :threshold

    def initialize(threshold:, rule: nil, jev_account: nil, cash_account: nil, whodunnit: nil)
      if rule.nil? == jev_account.nil?
        raise ArgumentError, "Choisis une règle, ou un compte proposé par Jev : il n'existe pas d'acceptation " \
                             "« toutes règles confondues »."
      end

      @rule = rule
      @jev_account = jev_account
      @cash_account = cash_account
      # Planché à 1 : un seuil de 0 accepterait tout ce que la borne propose,
      # ce qui vide de son sens la borne qu'on vient de poser.
      @threshold = threshold.to_i.clamp(1, 100)
      @whodunnit = whodunnit
    end

    # Les suggestions visées, les plus sûres d'abord.
    def suggestions
      scope = AllocationSuggestion.pending.confident_from(@threshold).ordered
                                  .where(cash_entry_id: CashEntry.pending.select(:id))
      scope = if @rule
                scope.where(allocation_rule_id: @rule.id)
              else
                scope.where(source: "jev", general_account_id: @jev_account.id)
              end
      scope = scope.where(cash_entry_id: CashEntry.where(cash_account_id: @cash_account.id).select(:id)) if @cash_account
      scope
    end

    # `ids` : les suggestions qu'un humain a vues dans un aperçu. Celles qui ne
    # sont plus dans la borne (décidées, sous le seuil) sont ignorées.
    def run!(ids: nil)
      scope = ids ? suggestions.where(id: ids) : suggestions
      accepted = 0
      skipped = 0

      scope.to_a.each do |suggestion|
        AcceptSuggestion.new(suggestion: suggestion, whodunnit: @whodunnit).run!
        accepted += 1
      rescue *SKIPPED
        skipped += 1
      end

      Result.new(accepted: accepted, skipped: skipped)
    end
  end
end
