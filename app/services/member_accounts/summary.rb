module MemberAccounts
  # Agrégats de l'écran de liste des comptes (issue #155).
  #
  # Le solde n'étant jamais stocké, l'afficher pour N comptes coûterait N
  # requêtes. Ce service les calcule TOUS en une seule requête groupée, les
  # injecte dans les objets, puis trie par solde décroissant — un tri qui ne
  # peut pas se faire en SQL, justement parce qu'il n'y a pas de colonne solde.
  class Summary
    EMPTY = { entries_cents: 0, entries_count: 0, last_entry_on: nil }.freeze

    def initialize(scope)
      @scope = scope
    end

    def accounts
      @accounts ||= begin
        list = @scope.to_a
        stats = stats_by_account_id(list.map(&:id))
        list.each { |account| account.prime_ledger!(**stats.fetch(account.id, EMPTY)) }
        list.sort_by { |account| [-account.balance_cents, account.name.to_s] }
      end
    end

    private

    def stats_by_account_id(ids)
      return {} if ids.empty?

      AccountEntry
        .where(member_account_id: ids)
        .group(:member_account_id)
        .pluck(Arel.sql("member_account_id, COALESCE(SUM(amount_cents), 0), COUNT(*), MAX(entry_date)"))
        .to_h do |account_id, sum, count, last_entry_on|
          [account_id, { entries_cents: sum.to_i, entries_count: count.to_i, last_entry_on: last_entry_on }]
        end
    end
  end
end
