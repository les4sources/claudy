module Finance
  # La revue des propositions d'une page de la file « À affecter » (Michael,
  # 2026-11-26) : « Proposer pour toutes les lignes affichées », puis valider
  # ou refuser.
  #
  # Les propositions sont rangées par LOT, et un lot a toujours une borne
  # qu'on peut nommer : une règle (« Bar Payconiq »), ou un compte proposé par
  # Jev (« Jev → 701001 Bar »). C'est la borne de `BulkAcceptSuggestions` :
  # on accepte d'un coup un paquet dont on a vu la nature, jamais un mélange.
  #
  # Une ligne qui a AUSSI une piste de rapprochement (un séjour, une facture,
  # le compte d'un habitant…) est montrée, mais décochée : la rapprocher garde
  # le lien avec ce qu'elle paie, l'affecter au compte proposé le perd.
  class ProposalReview
    Row = Data.define(:entry, :suggestion, :hint) do
      def checked? = hint.nil?
    end

    Lot = Data.define(:key, :source, :rule, :general_account, :rows) do
      def jev? = source == "jev"
      # Un lot sans borne nommable (les vieux « précédents du même IBAN ») ne
      # s'accepte qu'à la ligne.
      def bulk? = rule.present? || jev?
      def size = rows.size
      def total_cents = rows.sum { |row| row.suggestion.amount_cents }
      def min_confidence = rows.map { |row| row.suggestion.confidence }.min
      def checked_count = rows.count(&:checked?)
      def dom_id = "lot-#{key}"
    end

    attr_reader :entries

    # `pistes` : { cash_entry_id => indice } (`UnallocatedQueue#pistes_par_ligne`).
    def initialize(entries, pistes: {})
      @entries = entries.to_a
      @pistes = pistes
    end

    # Les lots, les plus gros d'abord : le bar passe en tête.
    def lots
      @lots ||= rows.group_by { |row| lot_key(row.suggestion) }.map do |key, lignes|
        suggestion = lignes.first.suggestion
        Lot.new(key: key, source: suggestion.source, rule: suggestion.allocation_rule, general_account: suggestion.general_account,
                rows: lignes.sort_by { |row| [-row.suggestion.confidence, row.entry.entry_date, row.entry.id] })
      end.sort_by { |lot| [-lot.size, lot.general_account.code.to_s] }
    end

    # Les lignes de la page encore en attente, sans proposition : elles se
    # traitent dans la file, une par une.
    def without_proposal
      @without_proposal ||= @entries.select { |entry| entry.status == "pending" && suggestion_for(entry).nil? }
    end

    def proposals_count = rows.size

    private

    def rows
      @rows ||= @entries.filter_map do |entry|
        next unless entry.status == "pending"

        suggestion = suggestion_for(entry)
        Row.new(entry: entry, suggestion: suggestion, hint: @pistes[entry.id]) if suggestion
      end
    end

    def suggestion_for(entry)
      entry.allocation_suggestions.select { |s| s.status == "pending" }.min_by { |s| [-s.confidence, s.id] }
    end

    def lot_key(suggestion)
      return "regle-#{suggestion.allocation_rule_id}" if suggestion.allocation_rule_id

      "#{suggestion.source}-#{suggestion.general_account_id}"
    end
  end
end
