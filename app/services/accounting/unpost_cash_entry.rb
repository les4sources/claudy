module Accounting
  # Annule la passation d'une ligne de trésorerie — pour la réaffecter.
  #
  # L'écriture n'est pas supprimée : elle est contre-passée, et les deux restent
  # au grand livre. Une correction qui efface son erreur oblige à croire sur
  # parole ; une correction qui la montre se relit.
  class UnpostCashEntry < ServiceBase
    class NotPosted < StandardError; end
    class ClosedFiscalYear < StandardError; end

    def initialize(cash_entry:, whodunnit: nil)
      @entry = cash_entry
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { cash_entry: @entry.id }) { unpost }
    end

    def run!
      unpost
    end

    private

    def unpost
      journal_entry = @entry.journal_entry
      raise NotPosted, "Cette ligne n'est pas comptabilisée." if journal_entry.blank?

      # Rendre « réaffectable » une ligne dont l'exercice est clos serait un
      # mensonge : sa date d'origine ne rentre plus nulle part, et on ne
      # rouvrirait le passé qu'en falsifiant la date du mouvement.
      if journal_entry.fiscal_year.closed?
        raise ClosedFiscalYear,
              "L'exercice #{journal_entry.fiscal_year.label} est clôturé — une correction s'y fait " \
              "par écriture de contre-passation datée de l'exercice ouvert, pas en réaffectant la ligne."
      end

      ApplicationRecord.transaction do
        # Toutes les écritures nées de cette ligne, y compris le miroir chez une
        # entité tierce : n'en contre-passer qu'une laisserait un compte courant
        # bancal chez l'autre.
        JournalEntry.where(source_type: "CashEntry", source_id: @entry.id).find_each do |ecriture|
          ReverseEntry.new(journal_entry: ecriture, entry_date: Date.current,
                           whodunnit: @whodunnit).run!
        end

        @entry.update!(status: "pending", allocated_at: nil)

        # Le lien vers le document est coupé APRÈS la sauvegarde de la ligne, et
        # par une écriture directe. Sauver le parent réécrit la clé étrangère de
        # son `has_one` chargé : détacher avant, c'est se faire rattacher juste
        # après, en silence — la ligne resterait alors comptabilisée et
        # inaffectable. L'association est réinitialisée dans la foulée pour que
        # l'objet en mémoire dise la même chose que la base.
        JournalEntry.where(source_type: "CashEntry", source_id: @entry.id).update_all(source_type: nil, source_id: nil)
        @entry.association(:journal_entries).reset
      end

      @entry
    end
  end
end
