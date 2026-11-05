module PurchaseInvoices
  # Défaire la passation d'une facture « À payer » qui n'a encore rien reçu
  # (Michael, 2026-11-05) : la facture VOO #26 était encodée deux fois, et une
  # fois « À payer » plus rien ne permettait de l'annuler — ni la modifier, ni
  # la contester, ni la remettre en traitement. Elle restait dans la file, et sa
  # charge comptait double.
  #
  # L'écriture d'achat n'est pas supprimée : elle est contre-passée, et les deux
  # restent au grand livre (même règle que `ExpenseReports::Unprocess`). Le lien
  # vers la facture est coupé ensuite, pour qu'un nouvel envoi au paiement
  # passe une écriture neuve au lieu de rendre la contre-passée.
  #
  # Deux issues : la facture revient « À traiter » pour être corrigée, ou elle
  # est contestée avec le motif (un doublon, une facture qui n'est pas pour
  # nous) et sort de la file.
  #
  # La contre-passation prend la date de l'écriture qu'elle annule, pour que la
  # charge disparaisse du même mois ; si ce mois est arrêté, elle est datée du
  # jour, sans toucher au mois promis au comptable.
  class Unpost < ServiceBase
    class Refused < StandardError; end

    OUTCOMES = %w[to_process disputed].freeze

    def initialize(purchase_invoice:, reason:, outcome: "to_process", whodunnit: nil)
      @invoice = purchase_invoice
      @reason = reason.to_s.strip
      @outcome = outcome.to_s
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { purchase_invoice: @invoice&.id }) { unpost }
    def run! = unpost

    def self.refusal_for(invoice)
      return "Seule une facture « À payer » se défait ainsi." unless invoice.to_pay?
      if invoice.allocated_cents.positive?
        return "Un paiement est déjà rapproché de cette #{invoice.kind_label.downcase} : défais d'abord le rapprochement sur sa ligne."
      end
      if !invoice.credit_note? && invoice.credited_cents.positive?
        return "Une note de crédit comptabilisée s'impute sur cette facture : défais-la d'abord."
      end

      ecritures(invoice).each do |entry|
        next unless entry.fiscal_year.closed?

        return "L'exercice #{entry.fiscal_year.label} est clôturé : la correction s'y fait par une écriture datée de l'exercice ouvert."
      end
      nil
    end

    def self.ecritures(invoice)
      JournalEntry.where(source: invoice, journal: "purchases").includes(:fiscal_year).to_a
    end

    private

    def unpost
      raise Refused, "Dis pourquoi tu défais cette facture (ex. « doublon de la facture #11 »)." if @reason.blank?
      raise Refused, "Issue inconnue : #{@outcome}." unless OUTCOMES.include?(@outcome)

      refus = self.class.refusal_for(@invoice)
      raise Refused, refus if refus

      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        ApplicationRecord.transaction do
          @invoice.lock!

          self.class.ecritures(@invoice).each do |ecriture|
            Accounting::ReverseEntry.new(journal_entry: ecriture, entry_date: date_for(ecriture),
                                         label: "Contre-passation — #{ecriture.label} (#{@reason})",
                                         whodunnit: @whodunnit).run!
          end
          JournalEntry.where(source: @invoice, journal: "purchases").update_all(source_type: nil, source_id: nil)

          if @outcome == "disputed"
            @invoice.update!(status: "disputed", dispute_reason: @reason, posted_at: nil)
          else
            @invoice.update!(status: "to_process", dispute_reason: nil, posted_at: nil)
          end
        end
      end

      # Une note de crédit défaite ne s'impute plus : sa facture peut
      # redevenir « À payer ».
      if @invoice.credit_note? && @invoice.credited_invoice
        RefreshPayment.new(purchase_invoice: @invoice.credited_invoice.reload, cascade: false).run!
      end

      @invoice.reload
    end

    def date_for(ecriture)
      MonthClosing.closed?(ecriture.entry_date) ? Date.current : ecriture.entry_date
    end
  end
end
