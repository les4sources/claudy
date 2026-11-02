module PurchaseInvoices
  # Le paiement d'une facture est un RAPPROCHEMENT (epic #240, décision 4).
  #
  # On ne coche pas « payée » : on constate que les lignes de trésorerie
  # affectées sur le `440000` avec cette facture en `document` couvrent son
  # total. Une case cochée à la main finit toujours par mentir ; un
  # rapprochement, non.
  #
  # Et il fonctionne dans les deux sens : si on défait l'affectation, la facture
  # redevient « À payer ». Un état qui ne sait que monter est un état faux.
  #
  # Les notes de crédit (2026-11-01) : une facture est réglée quand la banque
  # couvre ce qui reste après ses notes de crédit ; une note est réglée quand
  # elle s'impute entière sur sa facture, ou que le fournisseur a remboursé le
  # reste. Les deux se tiennent : on rafraîchit l'une, on rafraîchit l'autre
  # (`cascade: false` pour ne pas tourner en rond).
  class RefreshPayment < ServiceBase
    def initialize(purchase_invoice:, cascade: true)
      @invoice = purchase_invoice
      @cascade = cascade
    end

    def run = catch_error(context: { purchase_invoice: @invoice&.id }) { refresh }
    def run! = refresh

    private

    def refresh
      return @invoice if @invoice.blank?
      return @invoice unless %w[to_pay paid].include?(@invoice.status)

      if @invoice.total_cents.positive? && @invoice.remaining_cents <= 0
        @invoice.update_columns(status: "paid", paid_on: derniere_date || Date.current) unless @invoice.paid?
      elsif @invoice.paid?
        @invoice.update_columns(status: "to_pay", paid_on: nil)
      end

      cascade if @cascade

      # Un relevé de dépôt-vente en mode « l'artisan facture » est soldé par le
      # paiement de CETTE facture (epic #248, phase 3). Sans ce relais, le relevé
      # resterait « vérifié » alors que l'artisan a été payé.
      @invoice.reload.consignment_reports.each do |report|
        Consignments::RefreshSettlement.new(consignment_report: report).run!
      end

      @invoice.reload
    end

    def cascade
      if @invoice.credit_note?
        corrigee = @invoice.credited_invoice
        self.class.new(purchase_invoice: corrigee.reload, cascade: false).run! if corrigee
      else
        @invoice.credit_notes.where(status: PurchaseInvoice::FROZEN_STATUSES).find_each do |note|
          self.class.new(purchase_invoice: note, cascade: false).run!
        end
      end
    end

    # Le jour du dernier mouvement qui l'a réglée : le paiement, ou la note de
    # crédit qui a soldé la facture (ou la facture qui a absorbé la note).
    def derniere_date
      dates = @invoice.cash_allocations.includes(:cash_entry).map { |a| a.cash_entry&.entry_date }
      dates += @invoice.credit_notes.where(status: PurchaseInvoice::FROZEN_STATUSES).pluck(:issued_on) unless @invoice.credit_note?
      dates << @invoice.issued_on if @invoice.credit_note? && @invoice.imputed_cents.positive?
      dates.compact.max
    end
  end
end
