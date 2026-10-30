module Accounting
  # La balance des tiers (Michael, 2026-10-30) : à une date, ce qu'on doit à
  # chaque fournisseur, ou ce que chaque client nous doit, lu au grand livre.
  #
  # Jusque-là elle n'existait que dans le ZIP du comptable, au soir de la
  # clôture. Elle suit la même convention d'ouverture que tous les soldes
  # (`Accounting::Balances`) : l'ouverture est le solde au début de
  # l'exercice qui couvre la date ; quand l'exercice a un à-nouveau, il part de
  # zéro et l'à-nouveau compte parmi les mouvements, comme au grand livre.
  #
  # Un tiers = une ligne, tous ses comptes du côté choisi additionnés. Les
  # lignes posées sans tiers forment une ligne à part : c'est de l'argent dont
  # on ne sait pas à qui il revient, il ne disparaît pas du total.
  class ThirdPartyBalance
    # Le côté se lit au code du plan (PCMN) : 40 = créances clients,
    # 44 = dettes fournisseurs. Les notes de frais, porteurs, dépôt-vente et
    # partages de revenus passent aussi par le 44 : ce sont des fournisseurs
    # au sens comptable.
    SIDES = {
      "suppliers" => { prefix: "44", label: "Fournisseurs" },
      "customers" => { prefix: "40", label: "Clients" }
    }.freeze

    Row = Struct.new(:third_party, :accounts, :opening_cents, :debit_cents, :credit_cents, :due_sign,
                     keyword_init: true) do
      # Signé comme le compte : débit positif, crédit négatif.
      def balance_cents = opening_cents + debit_cents - credit_cents

      # Ce qui reste dû, du point de vue de la question posée : ce qu'on doit
      # au fournisseur, ce que le client nous doit. Négatif = une avance.
      def due_cents = balance_cents * due_sign
      def opening_due_cents = opening_cents * due_sign

      def settled? = balance_cents.zero?
      def name = third_party&.name || "(sans tiers)"
    end

    attr_reader :side, :as_of, :entities

    def initialize(as_of:, entities:, side: "suppliers")
      @side = SIDES.key?(side) ? side : "suppliers"
      @as_of = as_of
      @entities = Array(entities)
    end

    def label = SIDES.dig(side, :label)

    # Les dettes fournisseurs sont créditrices, les créances clients débitrices.
    def due_sign = side == "suppliers" ? -1 : 1

    def accounts
      @accounts ||= GeneralAccount.where("code LIKE ?", "#{SIDES.dig(side, :prefix)}%").order(:code).to_a
    end

    # Le premier jour lu en mouvements : le début de l'exercice de la date, ou
    # de l'année civile quand l'entité n'a pas d'exercice pour elle.
    def period_start(entity) = entity.fiscal_year_for(as_of)&.starts_on || as_of.beginning_of_year

    # Toutes les lignes, soldées comprises : les plus grosses dettes d'abord.
    def rows
      @rows ||= build_rows.sort_by { |row| [-row.due_cents, row.third_party ? 0 : 1, row.name.downcase] }
    end

    def open_rows = rows.reject(&:settled?)

    def total_due_cents = rows.sum(&:due_cents)
    def owed_cents = rows.sum { |row| [row.due_cents, 0].max }
    def advances_cents = rows.sum { |row| [row.due_cents, 0].min }.abs
    def unassigned_row = rows.find { |row| row.third_party.nil? && !row.settled? }

    private

    def build_rows
      return [] if accounts.empty?

      ids = accounts.map(&:id)
      by_id = accounts.index_by(&:id)
      rows = Hash.new do |hash, third_party_id|
        hash[third_party_id] = { accounts: Set.new, opening: 0, debit: 0, credit: 0 }
      end

      entities.each do |entity|
        start = period_start(entity)
        Balances.new(entity).before(start, by_third_party: true, only: ids).each do |(account_id, third_party_id), cents|
          rows[third_party_id][:opening] += cents
          rows[third_party_id][:accounts] << account_id
        end

        JournalLine.joins(:journal_entry)
                   .where(general_account_id: ids)
                   .where(journal_entries: { legal_entity_id: entity.id, entry_date: start..as_of })
                   .group(:third_party_id, :general_account_id)
                   .pluck(Arel.sql("journal_lines.third_party_id, journal_lines.general_account_id, " \
                                   "SUM(journal_lines.debit_cents), SUM(journal_lines.credit_cents)"))
                   .each do |third_party_id, account_id, debit, credit|
          rows[third_party_id][:debit] += debit.to_i
          rows[third_party_id][:credit] += credit.to_i
          rows[third_party_id][:accounts] << account_id
        end
      end

      third_parties = ThirdParty.where(id: rows.keys.compact).index_by(&:id)
      rows.map do |third_party_id, sums|
        Row.new(third_party: third_parties[third_party_id],
                accounts: sums[:accounts].map { |id| by_id[id] }.sort_by(&:code),
                opening_cents: sums[:opening], debit_cents: sums[:debit], credit_cents: sums[:credit],
                due_sign: due_sign)
      end
    end
  end
end
