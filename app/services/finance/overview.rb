module Finance
  # La page d'accueil de la Comptabilité, lue par le collectif des
  # administrateurs (Michael, 2026-10-30) : n'importe quel administrateur de
  # l'une des structures, comptable ou pas, doit y voir comment va chacune
  # aujourd'hui, ce qui l'attend dans les trois mois, ce qui pèse plus loin, et
  # ce qu'il faut trancher ensemble.
  #
  # Objet de lecture : il ne calcule rien de neuf, il rassemble les briques
  # qui font déjà foi (« Peut-on dépenser ? », la trésorerie, l'échéancier, le
  # budget, les prêts, les comptes annuels) entité par entité, et les traduit
  # en signaux.
  #
  # Ce qu'une entité ne permet pas de dire, la page le dit : sans compte
  # bancaire suivi, pas de verdict ; sans exercice dans Claudy, pas de
  # résultat. Un chiffre trompeur est pire qu'une case vide.
  class Overview
    DEADLINE_DAYS = Finance::Treasury::HORIZON_DAYS

    # Un signal : ce qu'un administrateur doit savoir avant de décider.
    # `level` : :no (à traiter), :warn (à surveiller), :info (à savoir).
    Signal = Data.define(:level, :entity, :text, :path)
    LEVELS = %i[no warn info].freeze

    # Une structure, vue par le collectif.
    class Health
      attr_reader :entity, :verdict, :today

      def initialize(entity:, verdict:, loans:, liabilities:, deadlines:, today:)
        @entity = entity
        @verdict = verdict
        @loans_group = loans.groups.find { |group| group.entity == entity }
        @liabilities = liabilities
        @deadlines = deadlines
        @today = today
      end

      # --- Aujourd'hui -----------------------------------------------------

      # Claudy suit-il son argent ? Il faut un compte de trésorerie actif.
      def tracked? = verdict.present?
      def treasury = verdict&.treasury

      # Le feu de la carte : celui de « Peut-on dépenser ? ».
      def status = verdict&.verdict || "inconnu"

      def balance_cents = verdict&.balance_cents.to_i

      # Le résultat ne se lit que si Claudy porte un exercice qui couvre
      # aujourd'hui et y a passé au moins une écriture.
      def fiscal_year = @fiscal_year ||= entity.fiscal_year_for(today)
      def books? = fiscal_year.present? && result_scope(fiscal_year.starts_on..today).exists?

      # Depuis le début de l'exercice : ce qui est rentré (classe 7), ce qui
      # est sorti (classe 6), et la différence.
      def year_start = fiscal_year&.starts_on
      def revenue_cents = year_totals[:revenue]
      def expense_cents = year_totals[:expense]
      def result_cents = revenue_cents - expense_cents

      # L'an dernier à la même date, pour comparer ce qui est comparable.
      def previous_result_cents
        return @previous_result_cents if defined?(@previous_result_cents)

        last_year = entity.fiscal_year_for(today << 12)
        @previous_result_cents =
          if last_year && last_year != fiscal_year
            totals = totals_for(last_year.starts_on..(today << 12))
            totals[:revenue] - totals[:expense] if totals[:any]
          end
      end

      # Les mouvements de banque et de caisse pas encore classés : tant qu'ils
      # attendent, résultat et marge sont incomplets.
      def pending_count = verdict&.pending_count.to_i
      def pending_cents = verdict&.pending_net_cents.to_i

      # Ce qu'elle doit encore, hors factures courantes : dettes et litiges
      # sans facture, prêts reçus.
      attr_reader :liabilities

      def liabilities_cents = liabilities.sum(&:remaining_cents)
      def short_term_loans_cents = @loans_group&.short_term_owed_cents.to_i
      def long_term_loans_cents = @loans_group&.long_term_owed_cents.to_i
      def loans_cents = short_term_loans_cents + long_term_loans_cents
      def owed_cents = liabilities_cents + loans_cents
      def lenders = @loans_group&.lenders.to_a.select { |lender| lender.owed_cents.positive? }

      # --- Les trois prochains mois ---------------------------------------

      def incoming_cents = verdict&.incoming_cents.to_i
      def outgoing_cents = verdict&.outgoing_cents.to_i
      def lowest_point = verdict&.lowest_point
      def horizon_balance_cents = treasury&.projection&.last&.balance_cents.to_i

      # Les échéances légales encore ouvertes jusqu'à la fin de l'horizon, les
      # retards d'abord.
      attr_reader :deadlines

      def overdue_deadlines = deadlines.select(&:overdue?)

      # --- Plus loin -------------------------------------------------------

      # Le budget de l'année en cours, s'il en existe un.
      def budget = @budget ||= Finance::BudgetSheet.new(legal_entity: entity, year: today.year, today: today)
      def budget? = !budget.draft?

      # Le budget de l'an prochain, celui qu'on prépare.
      def next_year = today.year + 1
      def next_budget = @next_budget ||= Finance::BudgetSheet.new(legal_entity: entity, year: next_year, today: today)
      def next_budget? = !next_budget.draft?

      # Les dettes et litiges qui tombent après les trois mois.
      def liabilities_later_cents = verdict&.liabilities_later_cents.to_i

      # Ce qu'elle possède moins ce qu'elle doit (fonds ou capitaux propres),
      # au bilan provisoire de l'exercice en cours.
      def equity_cents
        return @equity_cents if defined?(@equity_cents)

        @equity_cents = (annual_accounts.liabilities.find { |row| row.code == "10/15" }&.amount_cents if books?)
      end

      def company? = entity.form != "foundation"

      private

      def annual_accounts = @annual_accounts ||= Accounting::AnnualAccounts.new(fiscal_year)

      def year_totals
        @year_totals ||= books? ? totals_for(fiscal_year.starts_on..today) : { revenue: 0, expense: 0, any: false }
      end

      def result_scope(period)
        JournalLine.joins(:journal_entry, :general_account)
                   .where(journal_entries: { legal_entity_id: entity.id, entry_date: period, deleted_at: nil })
                   .where(general_accounts: { klass: [6, 7] })
                   .where.not(GeneralAccount::APPROPRIATION_SQL)
      end

      def totals_for(period)
        sums = result_scope(period).group("general_accounts.klass")
                                   .pluck(Arel.sql("general_accounts.klass, SUM(debit_cents), SUM(credit_cents)"))
                                   .to_h { |klass, debits, credits| [klass, [debits.to_i, credits.to_i]] }
        expense_debits, expense_credits = sums.fetch(6, [0, 0])
        revenue_debits, revenue_credits = sums.fetch(7, [0, 0])
        { revenue: revenue_credits - revenue_debits, expense: expense_debits - expense_credits, any: sums.any? }
      end
    end

    attr_reader :today

    def initialize(today: Date.current, loans: Finance::Loans.new, verdicts: nil)
      @today = today
      @loans = loans
      @verdicts = verdicts || Finance::SpendingVerdict.for_all(today: today, loans: loans)
    end

    # Toutes les structures actives, la Fondation d'abord, même celles que
    # Claudy ne suit pas encore : le collectif doit voir qu'elles existent.
    def entities
      @entities ||= LegalEntity.actives.sort_by { |entity| [entity.form == "foundation" ? 0 : 1, entity.name] }.map do |entity|
        Health.new(entity: entity, verdict: @verdicts.find { |verdict| verdict.entity == entity }, loans: @loans,
                   liabilities: liabilities.select { |liability| liability.legal_entity_id == entity.id },
                   deadlines: deadlines.select { |deadline| deadline.legal_entity == entity }, today: today)
      end
    end

    def find(entity_id) = entities.find { |health| health.entity.id.to_s == entity_id.to_s }

    # Ce qu'il faut trancher ou savoir, le plus grave d'abord.
    def signals(only: nil)
      (only ? [only] : entities).flat_map { |health| signals_for(health) }
                                .sort_by.with_index { |signal, index| [LEVELS.index(signal.level), index] }
    end

    private

    def liabilities = @liabilities ||= Liability.open.to_a

    def deadlines
      @deadlines ||= ComplianceDeadline.outstanding.where(due_on: ..(today + DEADLINE_DAYS)).ordered
                                       .includes(:purchase_invoice, compliance_obligation: :legal_entity).to_a
    end

    def signals_for(health)
      routes = Rails.application.routes.url_helpers
      name = health.entity.name
      list = []

      unless health.tracked?
        list << Signal.new(:info, health.entity, "Aucun compte bancaire de #{name} n'est suivi dans Claudy : " \
                                                 "on ne peut rien dire de son argent ici.", nil)
        return list + deadline_signals(health, routes)
      end

      verdict = health.verdict
      if verdict.verdict == "non" && verdict.margin_cents.negative?
        list << Signal.new(:no, health.entity, "#{name} : ce qui est en banque est déjà dû. Il manque " \
                                               "#{euros(-verdict.margin_cents)} pour couvrir les dettes, les prêts et les trois mois qui viennent.",
                           routes.finance_accounting_path(entity: health.entity.id))
      end
      low = health.lowest_point
      if low && low.balance_cents.negative?
        list << Signal.new(:no, health.entity, "La banque de #{name} passe sous zéro le " \
                                               "#{I18n.l(low.date, format: '%-d %B')} (#{euros(low.balance_cents)}) si rien ne change.",
                           routes.finance_accounting_path(entity: health.entity.id))
      end
      if verdict.verdict == "prudence"
        list << Signal.new(:warn, health.entity, "#{name} : il reste #{euros(verdict.margin_cents)} une fois tout payé, " \
                                                 "moins qu'un mois de charges fixes (#{euros(verdict.reserve_cents)}). " \
                                                 "Seulement l'indispensable.", routes.finance_accounting_path(entity: health.entity.id))
      end

      list.concat(deadline_signals(health, routes))

      if health.books? && health.result_cents.negative?
        list << Signal.new(:warn, health.entity, "Depuis le #{day(health.year_start)}, #{name} a dépensé " \
                                                 "#{euros(-health.result_cents)} de plus qu'elle n'a reçu.",
                           routes.finance_annual_accounts_path)
      end
      if health.equity_cents&.negative?
        list << Signal.new(:warn, health.entity, "#{name} doit plus qu'elle ne possède : il manque #{euros(-health.equity_cents)} " \
                                                 "pour que ses avoirs couvrent ses dettes.", routes.finance_annual_accounts_path)
      end
      if health.short_term_loans_cents.positive?
        lenders = health.lenders.reject(&:long_term?).size
        list << Signal.new(:warn, health.entity, "#{name} doit encore #{euros(health.short_term_loans_cents)} à " \
                                                 "#{lenders} prêteur#{'s' if lenders > 1} à court terme : de l'argent en banque qui n'est pas à elle.",
                           routes.finance_accounting_path(entity: health.entity.id))
      end
      if health.pending_count.positive?
        list << Signal.new(:info, health.entity, "#{health.pending_count} mouvement#{'s' if health.pending_count > 1} de banque " \
                                                 "ou de caisse de #{name} pas encore classé#{'s' if health.pending_count > 1} " \
                                                 "(#{euros(health.pending_cents)} nets) : les chiffres de cette page sont incomplets.",
                           routes.finance_cash_entries_path)
      end
      health.treasury.unanchored_accounts.each do |row|
        list << Signal.new(:info, health.entity, "#{row.account.name} n'a jamais été vérifié (relevé ou comptage) : " \
                                                 "son argent n'est pas compté ici.", routes.finance_cash_accounts_path)
      end
      if health.books? && today.month >= 9 && !health.next_budget?
        list << Signal.new(:info, health.entity, "Pas encore de budget #{health.next_year} pour #{name}.",
                           routes.finance_budget_path(entity_id: health.entity.id, year: health.next_year))
      end
      list
    end

    def deadline_signals(health, routes)
      late = health.overdue_deadlines
      return [] if late.empty?

      titles = late.first(3).map(&:display_title).join(", ") + (late.size > 3 ? "…" : "")
      [Signal.new(:no, health.entity, "#{late.size} obligation#{'s' if late.size > 1} légale#{'s' if late.size > 1} " \
                                      "de #{health.entity.name} en retard : #{titles}.", routes.finance_compliance_deadlines_path)]
    end

    def day(date) = date.day == 1 ? "1er #{I18n.l(date, format: '%B')}" : I18n.l(date, format: "%-d %B")

    def euros(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, unit: "€", precision: 0, format: "%n %u",
                                                                    delimiter: " ", separator: ",", negative_format: "−%n %u")
    end
  end
end
