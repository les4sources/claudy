module ExpenseReports
  # Le retour en arrière sur une note passée en traitement (epic #241, phase 1).
  #
  # L'écriture n'est pas supprimée : elle est contre-passée, et les deux restent
  # au grand livre — même règle que `Accounting::UnpostCashEntry`, pour la même
  # raison. Une correction qui efface son erreur oblige à croire sur parole.
  #
  # Le lien vers le document est coupé après la contre-passation : sans quoi
  # `PostDocument`, qui rend l'écriture existante d'un document, rendrait la
  # contre-passée au moment de repasser la note corrigée.
  #
  # La référence et le numéro de séquence, eux, RESTENT sur la note. Un numéro
  # attribué ne se réattribue pas (décision 4) — et l'abandonner ouvrirait un
  # trou dans la séquence que le contrôle signalerait à juste titre.
  class Unprocess < ServiceBase
    class NotProcessing < StandardError; end
    class AlreadyPaid < StandardError; end
    class ClosedFiscalYear < StandardError; end

    def initialize(expense_report:, whodunnit: nil)
      @report = expense_report
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { expense_report: @report.id }) { unprocess }
    end

    def run! = unprocess

    private

    def unprocess
      raise AlreadyPaid, "Cette note est payée — son règlement se défait d'abord." if @report.paid?
      raise NotProcessing, "Cette note n'est pas en traitement." unless @report.processing?

      entry = @report.journal_entry
      if entry.present? && entry.fiscal_year.closed?
        raise ClosedFiscalYear,
              "L'exercice #{entry.fiscal_year.label} est clôturé — la correction s'y fait par " \
              "écriture datée de l'exercice ouvert, pas en rouvrant la note."
      end

      PaperTrail.request(whodunnit: @whodunnit || "expense_reports") do
        ApplicationRecord.transaction do
          JournalEntry.where(source_type: "ExpenseReport", source_id: @report.id).find_each do |ecriture|
            Accounting::ReverseEntry.new(journal_entry: ecriture, entry_date: Date.current,
                                         whodunnit: @whodunnit).run!
          end

          @report.update!(status: "recorded", posted_at: nil)

          JournalEntry.where(source_type: "ExpenseReport", source_id: @report.id)
                      .update_all(source_type: nil, source_id: nil)
          @report.association(:journal_entries).reset
        end
      end

      @report.reload
    end
  end
end
