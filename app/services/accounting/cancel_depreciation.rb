module Accounting
  # Annule la dotation d'une immobilisation pour un exercice encore ouvert :
  # son écriture est contre-passée à la même date, puis la dotation retirée
  # du registre pour pouvoir être refaite (après correction du bien, par
  # exemple de sa durée).
  class CancelDepreciation < ServiceBase
    class Refused < ServiceError; end

    def initialize(depreciation:, whodunnit: nil)
      @depreciation = depreciation
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { depreciation: @depreciation.id }) { cancel }
    end

    def run!
      cancel
    end

    private

    def cancel
      fiscal_year = @depreciation.fiscal_year
      raise Refused, "L'exercice #{fiscal_year.label} est clôturé : cette dotation est définitive." if fiscal_year.closed?

      PaperTrail.request(whodunnit: @whodunnit || "accounting") do
        ApplicationRecord.transaction do
          entry = @depreciation.journal_entry
          if entry
            unless JournalEntry.exists?(reversal_of_id: entry.id)
              ReverseEntry.new(journal_entry: entry, entry_date: entry.entry_date, whodunnit: @whodunnit).run!
            end
            JournalEntry.where(id: entry.id).update_all(source_type: nil, source_id: nil)
          end
          @depreciation.reload.destroy!
        end
      end
    end
  end
end
