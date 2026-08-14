module Accounting
  # Contre-passe une écriture : une écriture miroir, débits et crédits inversés.
  #
  # C'est la seule correction possible d'une écriture verrouillée. Supprimer
  # laisserait un trou dans la numérotation, et un trou dans la numérotation est
  # exactement ce qu'un contrôle regarde en premier. Corriger sur place ferait
  # mentir un document déjà envoyé. La contre-passation, elle, raconte l'erreur
  # ET sa correction — c'est plus honnête et c'est plus simple à relire.
  class ReverseEntry < ServiceBase
    class AlreadyReversed < StandardError; end

    def initialize(journal_entry:, entry_date: nil, label: nil, whodunnit: nil)
      @entry = journal_entry
      @entry_date = entry_date || Date.current
      @label = label
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { entry: @entry.id }) { reverse }
    end

    def run!
      reverse
    end

    private

    def reverse
      # Interrogé en base et pas via l'association : une instance chargée avant
      # la première contre-passation garderait une association vide et laisserait
      # passer une seconde miroir.
      if JournalEntry.exists?(reversal_of_id: @entry.id)
        raise AlreadyReversed, "Cette écriture est déjà contre-passée."
      end

      fiscal_year = @entry.legal_entity.fiscal_year_for(@entry_date)
      raise PostDocument::MissingFiscalYear, "Aucun exercice n'ouvre le #{I18n.l(@entry_date)}." if fiscal_year.blank?

      PaperTrail.request(whodunnit: @whodunnit || "accounting") do
        ApplicationRecord.transaction do
          fiscal_year.lock!

          mirror = JournalEntry.new(
            fiscal_year: fiscal_year,
            legal_entity: @entry.legal_entity,
            journal: @entry.journal,
            number: next_number(fiscal_year),
            entry_date: @entry_date,
            label: @label || "Contre-passation — #{@entry.label}",
            reversal_of: @entry,
            posted_at: Time.current,
            whodunnit: @whodunnit
          )

          @entry.journal_lines.each do |line|
            mirror.journal_lines.build(
              general_account: line.general_account,
              analytic_account: line.analytic_account,
              team: line.team,
              debit_cents: line.credit_cents,
              credit_cents: line.debit_cents,
              label: line.label
            )
          end

          mirror.save!
          mirror
        end
      end
    end

    def next_number(fiscal_year)
      highest = JournalEntry.with_deleted do
        JournalEntry.where(fiscal_year_id: fiscal_year.id, journal: @entry.journal).maximum(:number)
      end
      highest.to_i + 1
    end
  end
end
