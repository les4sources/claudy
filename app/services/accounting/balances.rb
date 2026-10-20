module Accounting
  # Les soldes des comptes d'une entité à une date, selon UNE convention
  # d'ouverture (revue expert-comptable du 2026-10-20, point 7).
  #
  # Le grand livre cumulait tout l'historique, la balance ne lisait que la
  # période : avec 2022-2024 repris ET un à-nouveau 2025, le cumul comptait
  # deux fois. La règle tient désormais en deux phrases :
  #
  #   * les classes 6 et 7 repartent de zéro au début de chaque exercice — un
  #     résultat est celui d'une année, jamais d'une vie ;
  #   * les classes 1 à 5 partent de l'à-nouveau de l'exercice quand il en a un ;
  #     sans à-nouveau (les années reprises ligne à ligne), de tout l'historique.
  #
  # Un solde est signé du point de vue du compte : débit positif, crédit
  # négatif, comme `JournalLine#signed_cents`.
  class Balances
    def initialize(legal_entity)
      @entity = legal_entity
    end

    # Les soldes au soir de `date` (inclus), lus dans l'exercice qui la couvre.
    def through(date, by_third_party: false, only: nil)
      sums(fiscal_year: @entity.fiscal_year_for(date), last_day: date, by_third_party: by_third_party, only: only)
    end

    # Les soldes AVANT `date` (exclue) — l'ouverture d'un grand livre qui
    # commence ce jour-là. L'exercice de référence est celui de `date`, pas de
    # la veille : un grand livre lu à partir du 1er janvier part de zéro pour
    # les charges, et voit l'à-nouveau comme sa première ligne.
    def before(date, by_third_party: false, only: nil)
      sums(fiscal_year: @entity.fiscal_year_for(date), last_day: date - 1, by_third_party: by_third_party, only: only)
    end

    # L'exercice porte-t-il un à-nouveau vivant (ni contre-passé, ni
    # contre-passation) ? C'est lui qui coupe l'historique des classes 1 à 5.
    def self.opening_entries(fiscal_year)
      reversed = JournalEntry.where.not(reversal_of_id: nil).select(:reversal_of_id)
      JournalEntry.where(fiscal_year_id: fiscal_year.id, journal: "opening", reversal_of_id: nil)
                  .where.not(id: reversed)
    end

    def self.opening?(fiscal_year) = fiscal_year.present? && opening_entries(fiscal_year).exists?

    # Borne un `JournalLine.joins(:journal_entry)` des classes 1 à 5 sur la
    # même convention, pour toutes les entités à la fois : celles dont
    # l'exercice en cours a un à-nouveau ne sont lues qu'à partir de lui. C'est
    # ce que demande une lecture « tout l'historique » comme les prêts, qui
    # doublerait sinon chaque prêt repris dans l'à-nouveau.
    def self.since_opening(scope, as_of: Date.current)
      starts = LegalEntity.includes(:fiscal_years).filter_map do |entity|
        fiscal_year = entity.fiscal_year_for(as_of)
        [entity.id, fiscal_year.starts_on] if opening?(fiscal_year)
      end
      return scope if starts.empty?

      conditions = starts.map do |entity_id, start|
        JournalLine.sanitize_sql(["(journal_entries.legal_entity_id = ? AND journal_entries.entry_date >= ?)", entity_id, start])
      end
      others = JournalLine.sanitize_sql(["journal_entries.legal_entity_id NOT IN (?)", starts.map(&:first)])
      scope.where([others, *conditions].join(" OR "))
    end

    private

    def sums(fiscal_year:, last_day:, by_third_party:, only:)
      base = JournalLine.joins(:journal_entry, :general_account)
                        .where(journal_entries: { legal_entity_id: @entity.id })
                        .where("journal_entries.entry_date <= ?", last_day)
      base = base.where(general_account_id: only) if only

      result = Hash.new(0)
      [[[6, 7], fiscal_year&.starts_on], [[1, 2, 3, 4, 5], balance_sheet_start(fiscal_year)]].each do |klasses, start|
        scope = base.where(general_accounts: { klass: klasses })
        scope = scope.where("journal_entries.entry_date >= ?", start) if start
        group = by_third_party ? %i[general_account_id third_party_id] : :general_account_id
        scope.group(group).sum("journal_lines.debit_cents - journal_lines.credit_cents").each do |key, cents|
          result[key] += cents.to_i unless cents.to_i.zero?
        end
      end
      result
    end

    def balance_sheet_start(fiscal_year)
      fiscal_year.starts_on if self.class.opening?(fiscal_year)
    end
  end
end
