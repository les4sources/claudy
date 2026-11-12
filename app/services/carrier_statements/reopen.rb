module CarrierStatements
  # « Rouvrir en brouillon » un relevé émis, pour le corriger (Michael,
  # 2026-11-12 : relevé #8 d'Olivier, des rémunérations fausses et des lignes à
  # retirer, et aucun écran pour le faire).
  #
  # Un relevé émis est figé, et ses prestations avec lui : la fiche d'une
  # réservation relevée refuse de changer la rémunération et renvoie vers une
  # contre-passation. La voici. L'écriture d'émission est contre-passée (les
  # deux restent au grand livre), son lien vers le relevé est coupé, sans quoi
  # `PostDocument` rendrait l'écriture contre-passée au lieu de passer la
  # nouvelle, et le relevé redevient un brouillon. Ses lignes se corrigent ou se
  # retirent, puis il se réémet : nouvelle écriture, et le relevé corrigé part
  # par email comme à la première émission.
  #
  # Même forme que `Repost`. Refusé dès qu'un virement est rapproché du relevé :
  # il a été lettré sur la dette qu'on contre-passerait.
  class Reopen < ServiceBase
    class Refused < StandardError; end

    def initialize(statement:, reason: nil, whodunnit: nil)
      @statement = statement
      @reason = reason.to_s.strip.presence
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { carrier_statement: @statement&.id }) { reopen }
    def run! = reopen

    # Ce qui empêche de rouvrir, ou nil. Sert à l'écran pour taire le bouton.
    def refusal
      garde_fous!(journal_entry)
      nil
    rescue Refused => e
      e.message
    end

    def possible? = refusal.nil?

    private

    def journal_entry
      @journal_entry ||= JournalEntry.find_by(source: @statement, journal: "purchases")
    end

    def reopen
      old_entry = journal_entry
      garde_fous!(old_entry)

      PaperTrail.request(whodunnit: @whodunnit || "carrier_statement") do
        ApplicationRecord.transaction do
          @statement.lock!

          Accounting::ReverseEntry.new(journal_entry: old_entry, entry_date: Date.current,
                                       label: reversal_label(old_entry), whodunnit: @whodunnit).run!
          JournalEntry.where(source_type: "CarrierStatement", source_id: @statement.id)
                      .update_all(source_type: nil, source_id: nil)

          # `sent_at` part avec : la réémission enverra le relevé corrigé.
          @statement.update!(status: "draft", issued_at: nil, posted_at: nil, sent_at: nil)
        end
      end

      @statement.reload
    end

    def reversal_label(entry)
      ["Contre-passation — #{entry.label}", "(relevé rouvert pour correction#{" : #{@reason}" if @reason})"].join(" ")
    end

    def garde_fous!(entry)
      raise Refused, "Ce relevé est #{@statement.status_label.downcase} : il ne se rouvre pas." unless @statement.issued?
      raise Refused, "Ce relevé n'a pas d'écriture à contre-passer." if entry.blank?
      if @statement.cash_allocations.any?
        raise Refused, "Un virement est déjà rapproché de ce relevé : retire d'abord ce rapprochement."
      end
      if CarrierStatement.draft.where(human_id: @statement.human_id).where.not(id: @statement.id).exists?
        raise Refused, "#{@statement.human.name} a déjà un relevé en brouillon : émets-le ou supprime-le d'abord."
      end
      if entry.fiscal_year&.closed?
        raise Refused, "L'exercice #{entry.fiscal_year.label} est clôturé : l'écriture ne se contre-passe plus."
      end
      # La contre-passation est datée d'aujourd'hui, la réémission repassera
      # l'écriture à la fin de la période (`PostCarrierStatement`) : aucun des
      # deux mois ne doit être arrêté.
      [Date.current, @statement.period_to].uniq.each do |date|
        next unless MonthClosing.closed?(date)

        raise Refused, "#{I18n.l(date.beginning_of_month, format: '%B %Y')} est arrêté : " \
                       "l'écriture de ce relevé ne s'y repasse plus."
      end
    end
  end
end
