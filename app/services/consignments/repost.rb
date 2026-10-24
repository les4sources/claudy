module Consignments
  # « Repasser l'écriture » d'un relevé déjà réglé, quand le mode de règlement
  # de l'artisan a changé depuis (Michael, 2026-10-22 : le dépôt-vente d'Eline
  # passe en volontariat, sur la Fondation).
  #
  # L'écriture d'achat n'est pas modifiée : elle est contre-passée, et les deux
  # restent au grand livre, comme `ExpenseReports::Unprocess`. Le lien vers le
  # relevé est ensuite coupé, sans quoi `PostDocument` rendrait l'écriture
  # contre-passée au lieu de passer la nouvelle.
  #
  # Refusé dès qu'un virement est rapproché du relevé : ce paiement a été lettré
  # sur l'entité et le compte de l'ancienne écriture, et le changer sous lui
  # laisserait la dette ouverte d'un côté et payée de l'autre.
  class Repost < ServiceBase
    class Refused < StandardError; end

    def initialize(consignment_report:, whodunnit: nil)
      @report = consignment_report
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { consignment_report: @report&.id }) { repost }
    def run! = repost

    # Ce que la nouvelle écriture serait : [entité, code du compte de charge].
    def target
      [Accounting::PostConsignmentReport.entity_for(@report),
       Accounting::PostConsignmentReport.charge_code_for(@report)]
    end

    # L'écriture passée ne suit plus le mode de règlement de l'artisan.
    def needed?
      entry = @report.journal_entry
      return false if entry.blank? || !@report.consignor&.paid_by_transfer?

      entity, code = target
      entry.legal_entity_id != entity&.id ||
        entry.journal_lines.none? { |line| line.general_account&.code == code && line.debit_cents.to_i.positive? }
    end

    private

    def repost
      old_entry = @report.journal_entry
      garde_fous!(old_entry)

      PaperTrail.request(whodunnit: @whodunnit || "consignments") do
        ApplicationRecord.transaction do
          Accounting::ReverseEntry.new(journal_entry: old_entry, entry_date: Date.current,
                                       label: "Contre-passation — #{old_entry.label} (mode de règlement changé)",
                                       whodunnit: @whodunnit).run!
          JournalEntry.where(source_type: "ConsignmentReport", source_id: @report.id)
                      .update_all(source_type: nil, source_id: nil)
          @report.association(:journal_entries).reset

          entry = Accounting::PostConsignmentReport.new(consignment_report: @report,
                                                        whodunnit: @whodunnit).run!
          @report.update!(posted_at: Time.current, legal_entity: entry.legal_entity)
        end
      end

      @report.reload
    end

    def garde_fous!(entry)
      raise Refused, "Ce relevé n'a pas encore d'écriture : règle-le d'abord." if entry.blank?
      raise Refused, "Ce relevé est #{@report.status_label.downcase} : il ne se repasse plus." unless @report.verified?
      unless @report.consignor.paid_by_transfer?
        raise Refused, "#{@report.consignor.name} facture ses ventes : c'est sa facture d'achat qui porte la dette."
      end
      raise Refused, "L'écriture suit déjà le mode de règlement de l'artisan." unless needed?
      if @report.cash_allocations.any?
        raise Refused, "Un virement est déjà rapproché de ce relevé : retire d'abord ce rapprochement."
      end
      if entry.fiscal_year&.closed?
        raise Refused, "L'exercice #{entry.fiscal_year.label} est clôturé : l'écriture ne se repasse plus."
      end
      # La contre-passation est datée d'aujourd'hui, la nouvelle écriture du
      # jour de la vérification (`PostConsignmentReport`) : aucun des deux mois
      # ne doit être arrêté.
      [Date.current, @report.verified_at&.to_date || Date.current].uniq.each do |date|
        next unless MonthClosing.closed?(date)

        raise Refused, "#{I18n.l(date.beginning_of_month, format: '%B %Y')} est arrêté : " \
                       "l'écriture de ce relevé ne s'y repasse plus."
      end
    end
  end
end
