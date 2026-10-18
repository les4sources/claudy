module Finance
  # Le budget détaillé d'une entité pour une année (étape 4 du redressement,
  # Michael, 2026-10-18) : une ligne par pôle et par compte de charges ou de
  # produits, face au réel de référence.
  #
  # Le réel de référence est une année ENTIÈRE, jamais une année en cours
  # extrapolée : pour budgéter l'an prochain, les douze derniers mois complets
  # (décision de Michael du 2026-10-18) ; pour budgéter l'année en cours ou
  # une année passée, l'année civile d'avant.
  #
  # Tant que l'année n'a aucune ligne pour l'entité, la feuille est un
  # BROUILLON : chaque case propose le réel de référence, arrondi à l'euro, et
  # rien n'existe avant le premier enregistrement. On corrige des chiffres
  # plutôt que de les inventer.
  #
  # Le réel se lit sur les écritures de l'entité, par `team_id` : ce qui n'a
  # pas de pôle tombe dans « Sans pôle », pour que le total de la feuille soit
  # celui de l'entité.
  class BudgetSheet
    Row = Struct.new(:team, :account, :reference_cents, :line, :draft, keyword_init: true) do
      def key = BudgetSheet.key_for(team&.id, account.id)
      def expense? = account.klass == 6

      # Ce que la case affiche : la ligne enregistrée, ou en brouillon le réel
      # proposé. `nil` : rien de prévu sur ce compte.
      def budget_cents
        return line.amount_cents if line
        return BudgetSheet.proposal_for(reference_cents) if draft

        nil
      end

      def gap_cents = budget_cents.to_i - reference_cents
    end

    Totals = Struct.new(:revenue_cents, :expense_cents, keyword_init: true) do
      def net_cents = revenue_cents - expense_cents
    end

    Group = Struct.new(:team, :rows, keyword_init: true) do
      def name = team&.name || "Sans pôle"
      def budget = BudgetSheet.totals_of(rows, &:budget_cents)
      def reference = BudgetSheet.totals_of(rows, &:reference_cents)
    end

    def self.key_for(team_id, account_id) = "#{team_id || 0}-#{account_id}"

    # Une proposition se fait à l'euro près et jamais en négatif : un compte
    # de charges crédité sur l'année (un remboursement) ne se budgète pas.
    def self.proposal_for(cents) = [(cents / 100.0).round * 100, 0].max

    def self.totals_of(rows)
      Totals.new(revenue_cents: rows.reject(&:expense?).sum { |row| yield(row).to_i },
                 expense_cents: rows.select(&:expense?).sum { |row| yield(row).to_i })
    end

    def initialize(legal_entity:, year:, today: Date.current)
      @entity = legal_entity
      @year = year.to_i
      @today = today
    end

    attr_reader :entity, :year, :today

    def reference_period
      if year > today.year
        last = today.beginning_of_month - 1
        (last.beginning_of_month << 11)..last
      else
        Date.new(year - 1, 1, 1)..Date.new(year - 1, 12, 31)
      end
    end

    def reference_label
      period = reference_period
      if period.begin.month == 1 && period.end.month == 12 && period.begin.year == period.end.year
        "réel #{period.begin.year}"
      else
        debut = I18n.l(period.begin, format: "%B %Y")
        "réel #{debut.match?(/\A[aeiou]/i) ? "d'" : 'de '}#{debut} à #{I18n.l(period.end, format: '%B %Y')}"
      end
    end

    def lines
      @lines ||= BudgetLine.for_year(year).where(legal_entity: @entity).includes(:team, :general_account).to_a
    end

    def draft? = lines.empty?

    # Pôle par pôle, dans l'ordre alphabétique, « Sans pôle » à la fin ; les
    # comptes dans l'ordre du plan.
    def groups
      @groups ||= rows.group_by(&:team)
                      .map { |team, team_rows| Group.new(team: team, rows: team_rows.sort_by { |row| row.account.code }) }
                      .sort_by { |group| [group.team ? 0 : 1, group.name] }
    end

    def rows
      @rows ||= begin
        by_key = lines.index_by { |line| self.class.key_for(line.team_id, line.general_account_id) }
        keys = (reference_cents_by_key.keys + by_key.keys).uniq
        keys.map do |key|
          line = by_key[key]
          team_id, account_id = key.split("-").map(&:to_i)
          Row.new(team: line&.team || teams[team_id], account: line&.general_account || accounts[account_id],
                  reference_cents: reference_cents_by_key.fetch(key, 0), line: line, draft: draft?)
        end
      end
    end

    def budget = self.class.totals_of(rows, &:budget_cents)
    def reference = self.class.totals_of(rows, &:reference_cents)

    # Les lignes de trésorerie de l'entité qui attendent d'être affectées : leur
    # argent n'est dans aucun compte, donc dans aucune ligne de référence.
    def pending_scope
      CashEntry.pending.joins(:cash_account).where(cash_accounts: { legal_entity_id: @entity.id })
    end

    def pending_count = @pending_count ||= pending_scope.count
    def pending_cents = @pending_cents ||= pending_scope.sum(:amount_cents)

    # Enregistre les cases du formulaire, `{ "pôle-compte" => "1 200" }`. Une
    # case vidée supprime sa ligne ; un zéro sans ligne n'en crée pas. Rien
    # n'est écrit si une case est illisible : on ne garde pas la moitié d'un
    # budget. Renvoie les messages d'erreur, vide si tout est passé.
    def save(amounts)
      errors = []
      changes = amounts.to_h.filter_map do |key, value|
        team_id, account_id = key.to_s.split("-").map(&:to_i)
        cents = Liability.parse_euros(value)
        if cents.nil? && value.to_s.strip.present?
          errors << "« #{value} » n'est pas un montant lisible (exemple : 12 000 ou 1 250,50)."
          next
        end
        [team_id.zero? ? nil : team_id, account_id, cents]
      end
      return errors if errors.any?

      BudgetLine.transaction do
        changes.each do |team_id, account_id, cents|
          line = BudgetLine.find_or_initialize_by(year: year, legal_entity: @entity, team_id: team_id,
                                                  general_account_id: account_id)
          if cents.nil? || (cents.zero? && line.new_record?)
            line.destroy! if line.persisted?
          else
            line.amount_cents = cents
            line.save!
          end
        end
      end
      @lines = @rows = @groups = nil
      []
    rescue ActiveRecord::RecordInvalid => e
      [e.record.errors.full_messages.to_sentence]
    end

    private

    # { "pôle-compte" => centimes } : charges au débit, produits au crédit.
    def reference_cents_by_key
      @reference_cents_by_key ||=
        JournalLine.joins(:journal_entry, :general_account)
                   .where(journal_entries: { legal_entity_id: @entity.id, entry_date: reference_period, deleted_at: nil })
                   .where(general_accounts: { klass: BudgetLine::CLASSES })
                   .group(:team_id, :general_account_id, "general_accounts.klass")
                   .pluck(Arel.sql("journal_lines.team_id, journal_lines.general_account_id, general_accounts.klass, " \
                                   "SUM(debit_cents), SUM(credit_cents)"))
                   .each_with_object({}) do |(team_id, account_id, klass, debits, credits), result|
                     cents = klass == 6 ? debits.to_i - credits.to_i : credits.to_i - debits.to_i
                     result[self.class.key_for(team_id, account_id)] = cents
                   end
    end

    def teams
      # Un pôle supprimé depuis garde son réel : il reste nommé.
      @teams ||= Team.with_deleted { Team.where(id: reference_cents_by_key.keys.map { |key| key.split("-").first.to_i }).to_a }
                     .index_by(&:id)
    end

    def accounts
      @accounts ||= GeneralAccount.with_deleted do
        GeneralAccount.where(id: reference_cents_by_key.keys.map { |key| key.split("-").last.to_i }).to_a
      end.index_by(&:id)
    end
  end
end
