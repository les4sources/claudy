module Finance
  # Les prêts reçus (Michael, 2026-10-13) : qui a prêté, combien, ce qui est
  # déjà remboursé, ce qui reste dû. Un prêt de trésorerie entre sur le compte
  # en banque comme une recette ; sans cette vue, il ressemble à de la marge.
  #
  # Objet de lecture, comme `Treasury` : la seule source est le grand livre,
  # les comptes 17 (emprunts), toutes années confondues. Un crédit est un
  # emprunt, un débit un remboursement. Le prêteur est le tiers de la ligne ;
  # sans tiers, c'est le compte lui-même (« 174006 Prêt CT Muriel » nomme déjà
  # son prêteur).
  #
  # Une ligne de banque pas encore comptabilisée n'y est pas : tant qu'elle
  # attend dans la file « À affecter », le prêt n'existe pas pour la compta.
  class Loans
    ACCOUNT_PREFIX = "17".freeze

    Lender = Struct.new(:entity, :account, :third_party, :borrowed_cents, :repaid_cents, :last_movement_on,
                        keyword_init: true) do
      def owed_cents = borrowed_cents - repaid_cents
      def name = third_party&.name || account.name
      def named? = third_party.present?
    end

    Group = Struct.new(:entity, :lenders, keyword_init: true) do
      def owed_cents = lenders.sum(&:owed_cents)
    end

    # Les prêteurs à qui on doit encore quelque chose, par entité, le plus
    # gros d'abord. Un prêt remboursé disparaît : il ne pèse plus.
    def groups
      @groups ||= lenders.reject { |lender| lender.owed_cents.zero? }
                         .group_by(&:entity)
                         .map { |entity, rows| Group.new(entity: entity, lenders: rows.sort_by { |r| [-r.owed_cents, r.name] }) }
                         .sort_by { |group| group.entity.name }
    end

    def owed_cents = groups.sum(&:owed_cents)
    def any? = groups.any?

    private

    def lenders
      rows = JournalLine.joins(:journal_entry, :general_account)
                        .where(journal_entries: { deleted_at: nil })
                        .where("general_accounts.code LIKE ?", "#{ACCOUNT_PREFIX}%")
                        .group("journal_entries.legal_entity_id", "journal_lines.general_account_id", "journal_lines.third_party_id")
                        .pluck("journal_entries.legal_entity_id", "journal_lines.general_account_id", "journal_lines.third_party_id",
                               Arel.sql("SUM(journal_lines.credit_cents)"), Arel.sql("SUM(journal_lines.debit_cents)"),
                               Arel.sql("MAX(journal_entries.entry_date)"))
      return [] if rows.empty?

      entities = LegalEntity.where(id: rows.map(&:first)).index_by(&:id)
      accounts = GeneralAccount.where(id: rows.map(&:second)).index_by(&:id)
      third_parties = ThirdParty.where(id: rows.map { |row| row[2] }.compact).index_by(&:id)

      rows.map do |entity_id, account_id, third_party_id, credits, debits, last_on|
        Lender.new(entity: entities[entity_id], account: accounts[account_id], third_party: third_parties[third_party_id],
                   borrowed_cents: credits.to_i, repaid_cents: debits.to_i, last_movement_on: last_on)
      end
    end
  end
end
