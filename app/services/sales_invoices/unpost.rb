module SalesInvoices
  # Remet à plat l'écriture de vente d'une facture, avant de la corriger ou de
  # la retirer du registre (Michael, 2026-10-30).
  #
  # L'écriture n'est pas modifiée : elle est contre-passée À SA DATE, comme
  # `Accounting::UnpostCashEntry`, et les deux restent au grand livre. Datée
  # du jour, l'annulation d'une vente de juin tomberait en octobre pendant que
  # la facture corrigée se repasse en juin : la TVA de juin serait comptée deux
  # fois. D'où les refus : un exercice clôturé ou un mois arrêté ne se rouvrent
  # pas par la bande ; la correction s'y fait par une note de crédit.
  #
  # Le lien entre l'écriture et la facture est ensuite coupé, sans quoi
  # `PostDocument` rendrait l'écriture contre-passée au lieu de passer la
  # nouvelle.
  class Unpost
    class Refused < StandardError; end

    def initialize(sales_invoice:, whodunnit: nil)
      @invoice = sales_invoice
      @whodunnit = whodunnit
    end

    def run!
      entry = @invoice.journal_entry
      return @invoice if entry.blank?

      check!(entry)
      Accounting::ReverseEntry.new(journal_entry: entry, entry_date: entry.entry_date, whodunnit: @whodunnit).run!
      JournalEntry.where(source_type: "SalesInvoice", source_id: @invoice.id).update_all(source_type: nil, source_id: nil)
      @invoice.update_columns(posted_at: nil, journal_entry_id: nil)
      @invoice
    end

    def check!(entry)
      if entry.source_type != "SalesInvoice" || entry.source_id != @invoice.id
        raise Refused, "L'écriture de cette facture est une écriture reprise : elle ne se contre-passe pas d'ici."
      end
      if entry.fiscal_year&.closed?
        raise Refused, "L'exercice #{entry.fiscal_year.label} est clôturé : émets une note de crédit plutôt que de corriger la facture."
      end
      return unless MonthClosing.closed?(entry.entry_date)

      raise Refused, "#{I18n.l(entry.entry_date.beginning_of_month, format: '%B %Y')} est arrêté : " \
                     "émets une note de crédit plutôt que de corriger la facture."
    end
  end
end
