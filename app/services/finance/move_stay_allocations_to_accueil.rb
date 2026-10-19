module Finance
  # Range sur le pôle Accueil les affectations de séjour faites avant la règle
  # (Michael, 2026-10-19 : « quand on assigne une ligne de trésorerie à un
  # séjour, ça doit se lier au pôle Accueil »). `VentilateStay` s'en charge pour
  # les nouvelles ; ce service reprend les anciennes.
  #
  # Sont concernées les parts qui rapprochent un séjour (document `Stay`) et
  # qui ne sont pas encore sur l'Accueil.
  #
  # Rien ne se réécrit en place : chaque ligne passe par
  # `ReallocateCashEntry`, qui contre-passe l'écriture d'une ligne
  # comptabilisée puis la repasse. Seul le pôle des parts concernées change ;
  # les autres parts de la ligne restent telles quelles. Une ligne d'un mois
  # arrêté ou d'un exercice clôturé est refusée et sort dans le rapport.
  class MoveStayAllocationsToAccueil < ServiceBase
    class NoAccueil < StandardError; end

    WHODUNNIT = "rake finance:sejours_pole_accueil".freeze

    Item = Struct.new(:cash_entry, :allocations, :error, keyword_init: true) do
      def amount_cents = allocations.sum(&:amount_cents)
    end

    Report = Struct.new(:accueil, :moved, :refused, keyword_init: true) do
      def allocations = (moved + refused).flat_map(&:allocations)
    end

    def initialize(dry_run: true, whodunnit: WHODUNNIT)
      @dry_run = dry_run
      @whodunnit = whodunnit
    end

    def run = catch_error { move }
    def run! = move

    private

    def move
      accueil = Team.accueil
      raise NoAccueil, "Aucun pôle dont le nom contient « Accueil » : rien à faire." if accueil.nil?

      report = Report.new(accueil: accueil, moved: [], refused: [])

      concernees(accueil).group_by(&:cash_entry).sort_by { |entry, _| [entry.entry_date, entry.id] }
                         .each do |entry, allocations|
        item = Item.new(cash_entry: entry, allocations: allocations)
        item.error = deplacer(entry, allocations.map(&:id), accueil)
        (item.error ? report.refused : report.moved) << item
      end

      report
    end

    def concernees(accueil)
      CashAllocation.where(document_type: "Stay")
                    .where("cash_allocations.team_id IS NULL OR cash_allocations.team_id <> ?", accueil.id)
                    .includes(:team, :cash_entry)
                    .order(:id)
                    .to_a
    end

    # Renvoie le motif du refus, ou nil. En simulation, on prévoit les refus
    # que `ReallocateCashEntry` opposerait, sans rien écrire.
    def deplacer(entry, ids, accueil)
      return refus_prevu(entry) if @dry_run

      parts = entry.cash_allocations.ordered.map do |allocation|
        {
          id: allocation.id,
          general_account_id: allocation.general_account_id,
          team_id: ids.include?(allocation.id) ? accueil.id : allocation.team_id,
          legal_entity_id: allocation.legal_entity_id,
          amount_cents: allocation.amount_cents
        }
      end
      ReallocateCashEntry.new(cash_entry: entry, parts: parts, whodunnit: @whodunnit).run!
      nil
    rescue ReallocateCashEntry::Refused => e
      e.message
    end

    def refus_prevu(entry)
      return "ligne exclue" if entry.status == "excluded"
      return "#{I18n.l(entry.entry_date.beginning_of_month, format: '%B %Y')} est arrêté" if MonthClosing.closed?(entry.entry_date)

      clos = JournalEntry.where(source_type: "CashEntry", source_id: entry.id).includes(:fiscal_year)
                         .map(&:fiscal_year).find { |exercice| exercice&.closed? }
      "l'exercice #{clos.label} est clôturé" if clos
    end
  end
end
