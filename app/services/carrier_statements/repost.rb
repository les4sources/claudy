module CarrierStatements
  # « Repasser au nom de… » un relevé déjà émis, quand le porteur est payé par
  # un autre tiers depuis (Michael, 2026-10-30 : le relevé de Steph doit passer
  # par la SPRL Domaine d'Ahinvaux, comme ceux d'Olivier, Seb et Magali).
  #
  # Le tiers est figé à la génération (`Generate`), et l'écriture d'émission
  # porte la dette au `440000` à son nom : changer la fiche du porteur après
  # coup ne touche ni l'un ni l'autre. Le virement à la SPRL se lettrerait alors
  # sur la SPRL, et la dette resterait ouverte au nom du porteur.
  #
  # Même forme que `Consignments::Repost` : l'écriture d'achat est contre-passée,
  # les deux restent au grand livre ; le lien vers le relevé est coupé, sans quoi
  # `PostDocument` rendrait l'écriture contre-passée au lieu de passer la
  # nouvelle. Aucun email ne part : le relevé a déjà été envoyé.
  #
  # Refusé dès qu'un virement est rapproché du relevé : il a été lettré sur
  # l'ancien tiers.
  class Repost < ServiceBase
    class Refused < StandardError; end

    def initialize(statement:, whodunnit: nil)
      @statement = statement
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { carrier_statement: @statement&.id }) { repost }
    def run! = repost

    # Le tiers que la nouvelle écriture porterait : celui de la fiche du
    # porteur, ou personne (le porteur lui-même).
    def target = @statement.human.carrier_payee

    # Le relevé n'est plus adressé à qui la fiche du porteur dit de payer.
    def needed?
      @statement.issued? && journal_entry.present? && @statement.third_party_id != target&.id
    end

    # Le nom de qui recevra le relevé une fois repassé.
    def target_name = target&.name || @statement.human.name

    private

    def journal_entry
      @journal_entry ||= JournalEntry.find_by(source: @statement, journal: "purchases")
    end

    def repost
      old_entry = journal_entry
      garde_fous!(old_entry)

      PaperTrail.request(whodunnit: @whodunnit || "carrier_statement") do
        ApplicationRecord.transaction do
          @statement.lock!

          Accounting::ReverseEntry.new(journal_entry: old_entry, entry_date: Date.current,
                                       label: "Contre-passation — #{old_entry.label} (payé via #{target_name})",
                                       whodunnit: @whodunnit).run!
          JournalEntry.where(source_type: "CarrierStatement", source_id: @statement.id)
                      .update_all(source_type: nil, source_id: nil)

          @statement.update!(third_party: target)
          Accounting::PostCarrierStatement.new(statement: @statement, whodunnit: @whodunnit).run!
          @statement.update!(posted_at: Time.current)
        end
      end

      @statement.reload
    end

    def garde_fous!(entry)
      raise Refused, "Ce relevé n'a pas encore d'écriture : émets-le d'abord." if entry.blank?
      raise Refused, "Ce relevé est #{@statement.status_label.downcase} : il ne se repasse plus." unless @statement.issued?
      raise Refused, "Ce relevé est déjà adressé à #{target_name}." unless needed?
      if @statement.cash_allocations.any?
        raise Refused, "Un virement est déjà rapproché de ce relevé : retire d'abord ce rapprochement."
      end
      if entry.fiscal_year&.closed?
        raise Refused, "L'exercice #{entry.fiscal_year.label} est clôturé : l'écriture ne se repasse plus."
      end
      # La contre-passation est datée d'aujourd'hui, la nouvelle écriture de la
      # fin de période (`PostCarrierStatement`) : aucun des deux mois ne doit
      # être arrêté.
      [Date.current, @statement.period_to].uniq.each do |date|
        next unless MonthClosing.closed?(date)

        raise Refused, "#{I18n.l(date.beginning_of_month, format: '%B %Y')} est arrêté : " \
                       "l'écriture de ce relevé ne s'y repasse plus."
      end
    end
  end
end
