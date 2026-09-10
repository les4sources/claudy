module Finance
  # La feuille de caisse d'un mois (epic #243, phase 2).
  #
  # Objet de lecture : le compte de caisse, le mois, ses lignes, et les deux
  # soldes qui encadrent la page.
  #
  # LE SOLDE D'OUVERTURE EST COMPTABLE, pas la somme des lignes de la feuille :
  # c'est le solde du compte général de la caisse au 1er du mois, tel que le
  # grand livre le connaît. Une feuille qui repartirait de sa propre somme
  # tomberait toujours juste — y compris quand la comptabilité, elle, ne l'est
  # pas — et l'écran perdrait exactement ce qu'on lui demande de dire.
  class CashSheet
    Row = Struct.new(:entry, :balance_cents, keyword_init: true)

    def initialize(cash_account:, month:)
      @account = cash_account
      @month = month.beginning_of_month
    end

    attr_reader :account, :month

    def from = @month
    def to = @month.end_of_month

    def previous_month = @month - 1.month
    def next_month = @month + 1.month

    def closed? = MonthClosing.closed?(@month)

    def entries
      @entries ||= CashEntry.where(cash_account_id: @account.id, entry_date: from..to)
                            .where.not(status: "excluded")
                            .includes(:cash_motif, cash_allocations: %i[general_account team])
                            .order(:entry_date, :id)
                            .to_a
    end

    def excluded_entries
      @excluded_entries ||= CashEntry.where(cash_account_id: @account.id, entry_date: from..to)
                                     .where(status: "excluded").order(:entry_date, :id).to_a
    end

    # Chaque ligne avec le solde courant APRÈS elle : c'est ce qu'on lit sur la
    # feuille papier, et c'est ce qui permet de repérer d'un coup d'œil le jour
    # où la caisse a décroché.
    def rows
      @rows ||= begin
        running = opening_cents
        entries.map do |entry|
          running += entry.amount_cents
          Row.new(entry: entry, balance_cents: running)
        end
      end
    end

    def opening_cents
      @opening_cents ||= accounting_balance_before(from)
    end

    def closing_cents = opening_cents + entries.sum(&:amount_cents)

    def incoming_cents = entries.select { |e| e.amount_cents.positive? }.sum(&:amount_cents)
    def outgoing_cents = entries.select { |e| e.amount_cents.negative? }.sum(&:amount_cents)

    private

    # Le solde du compte général de la caisse, pour son entité, avant une date.
    def accounting_balance_before(date)
      lines = JournalLine.joins(:journal_entry)
                         .where(general_account_id: @account.general_account_id)
                         .where(journal_entries: { legal_entity_id: @account.legal_entity_id })
                         .where(journal_entries: { entry_date: ...date })

      lines.sum(:debit_cents) - lines.sum(:credit_cents)
    end
  end
end
