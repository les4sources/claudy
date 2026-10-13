module Finance
  # Enregistre une règle d'affectation et recalcule les suggestions des lignes
  # qu'elle touche, et seulement celles-là.
  #
  # Une règle passe avant Jev (`SuggestAllocations`) : elle est écrite par un
  # humain. Une proposition de Jev encore en attente sur une ligne que la règle
  # reconnaît est donc retirée, et la ligne repasse par l'ordre normal — la
  # première règle qui correspond gagne. Une proposition DÉCIDÉE (acceptée,
  # refusée) ne bouge jamais.
  #
  # Corriger les critères d'une règle retire ses propositions encore en attente,
  # puis les refait : une ligne qu'elle ne reconnaît plus perd sa proposition.
  class ApplyAllocationRule
    Result = Struct.new(:rule, :proposed, :proposed_cents, :replaced_jev, :others, :refused, keyword_init: true)

    def initialize(rule:, whodunnit: nil)
      @rule = rule
      @whodunnit = whodunnit
    end

    def run!
      ApplicationRecord.transaction do
        @rule.save!

        stale = AllocationSuggestion.pending.where(allocation_rule_id: @rule.id).to_a
        matched = @rule.active? ? open_entries.select { |entry| @rule.match(entry) } : []
        jev = AllocationSuggestion.pending.where(source: "jev", cash_entry_id: matched.map(&:id)).to_a
        (stale + jev).each { |suggestion| suggestion.soft_delete!(validate: false) }

        touched = (matched.map(&:id) + stale.map(&:cash_entry_id)).uniq
        SuggestAllocations.new(cash_entries: CashEntry.where(id: touched).includes(:cash_allocations),
                               whodunnit: @whodunnit).run!

        result(matched, jev)
      end
    end

    private

    # Les lignes qu'une règle peut encore toucher : à affecter, sans
    # affectation, pas comptabilisées.
    def open_entries
      CashEntry.pending.includes(:cash_account, :cash_allocations, :journal_entries).to_a
               .select { |entry| entry.cash_allocations.empty? && !entry.posted? }
    end

    def result(matched, jev)
      ids = matched.map(&:id)
      pending = AllocationSuggestion.pending.where(cash_entry_id: ids).to_a
      mine = pending.select { |suggestion| suggestion.allocation_rule_id == @rule.id }
      refused = AllocationSuggestion.where(status: "rejected", allocation_rule_id: @rule.id, cash_entry_id: ids)
                                    .where.not(cash_entry_id: mine.map(&:cash_entry_id)).distinct.count(:cash_entry_id)

      Result.new(rule: @rule, proposed: mine.size, proposed_cents: mine.sum { |s| s.amount_cents.abs },
                 replaced_jev: jev.size, others: pending.size - mine.size, refused: refused)
    end
  end
end
