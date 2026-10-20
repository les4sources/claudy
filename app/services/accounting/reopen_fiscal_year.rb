module Accounting
  # Rouvrir un exercice clôturé : la seule porte de sortie d'une clôture, et
  # elle est étroite.
  #
  # Le formulaire des exercices ne change plus le statut (revue du 2026-10-20 :
  # « un exercice clôturé se rouvre par le formulaire »). Reste ce geste-ci,
  # délibéré et motivé, réservé au DERNIER exercice clôturé de l'entité : rouvrir
  # 2023 sous un 2024 clôturé ferait mentir l'à-nouveau 2024, qui en dépend.
  #
  # Rien ne s'efface. L'affectation du résultat et l'à-nouveau posés par la
  # clôture sont contre-passés à leur propre date, les écritures déverrouillées,
  # et le motif reste dans l'historique.
  class ReopenFiscalYear < ServiceBase
    class Refused < ServiceError; end

    def initialize(fiscal_year:, reason:, whodunnit: nil)
      @fiscal_year = fiscal_year
      @reason = reason.to_s.strip
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { fiscal_year: @fiscal_year.id }) { reopen }
    end

    def run!
      reopen
    end

    # Ce qui empêche la réouverture, en clair — ou nil.
    def refusal
      return "L'exercice #{@fiscal_year.label} n'est pas clôturé." unless @fiscal_year.closed?

      later = @fiscal_year.legal_entity.fiscal_years.where("starts_on > ?", @fiscal_year.starts_on)
                          .select(&:closed?).min_by(&:starts_on)
      return "Rouvre d'abord l'exercice #{later.label} : on ne rouvre que le dernier exercice clôturé." if later

      "Donne le motif de la réouverture : il reste dans l'historique." if @reason.blank?
    end

    private

    def reopen
      refused = refusal
      raise Refused, refused if refused

      whodunnit = [@whodunnit || "accounting", "réouverture : #{@reason}"].join(" — ").first(250)
      PaperTrail.request(whodunnit: whodunnit) do
        ApplicationRecord.transaction do
          @fiscal_year.lock!
          @fiscal_year.update!(status: "open", closed_at: nil)
          JournalEntry.where(fiscal_year_id: @fiscal_year.id).update_all(locked_at: nil)

          produced = JournalEntry.where(source_type: "FiscalYear", source_id: @fiscal_year.id)
          produced.find_each do |entry|
            next if JournalEntry.exists?(reversal_of_id: entry.id)

            ReverseEntry.new(journal_entry: entry, entry_date: entry.entry_date, whodunnit: whodunnit,
                             label: "Contre-passation — #{entry.label} (réouverture #{@fiscal_year.label})").run!
          end
          # Détachées de l'exercice : sans ça, la prochaine clôture retrouverait
          # ces écritures contre-passées par l'idempotence de `PostDocument` au
          # lieu de poser les siennes.
          produced.update_all(source_type: nil, source_id: nil)
          @fiscal_year
        end
      end
    end
  end
end
