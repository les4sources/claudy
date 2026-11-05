module SalesInvoices
  # Corriger une facture de vente déjà au registre (Michael, 2026-10-30).
  #
  # Une facture comptabilisée dont on change ce qui fait l'écriture (entité,
  # tiers, numéro, date, type, total, lignes) est contre-passée puis repassée
  # (`Unpost`). Une note ou un PDF ne touchent pas au grand livre : rien n'est
  # contre-passé pour eux.
  #
  # Le tiers et l'entité ne bougent plus dès qu'un encaissement est rapproché :
  # il a été passé en 400000 sur ce tiers, chez cette entité, et la facture
  # resterait ouverte d'un côté et payée de l'autre.
  class Correct < ServiceBase
    class Refused < StandardError; end

    ACCOUNTING_ATTRIBUTES = %w[legal_entity_id third_party_id number issued_on total_cents kind].freeze

    def initialize(sales_invoice:, attributes:, document: nil, whodunnit: nil)
      @invoice = sales_invoice
      @attributes = attributes.to_h.stringify_keys
      @document = document
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { sales_invoice: @invoice&.id }) { correct }
    def run! = correct

    def invoice = @invoice

    private

    def correct
      ancienne_corrigee = @invoice.credited_invoice

      PaperTrail.request(whodunnit: @whodunnit || "sales_invoice") do
        ApplicationRecord.transaction do
          @invoice.lock!
          @invoice.assign_attributes(@attributes)

          if (@invoice.changed & %w[legal_entity_id third_party_id]).any? && @invoice.cash_allocations.any?
            raise Refused, "Un encaissement est rapproché de cette facture : retire-le avant de changer de tiers ou d'entité."
          end

          if repasser? && @invoice.attached?
            raise Refused, "Cette facture pointe une écriture reprise (#{@invoice.journal_entry.reference}) : elle ne se " \
                           "contre-passe pas d'ici. Retire-la du registre, puis rattache-la à nouveau."
          end

          Unpost.new(sales_invoice: @invoice, whodunnit: @whodunnit).run! if repasser?

          @invoice.save!
          @invoice.document.attach(@document) if @document.present?

          if @invoice.on_issue? && !@invoice.posted?
            Accounting::PostSalesInvoice.new(sales_invoice: @invoice, whodunnit: @whodunnit).run!
          end

          # Le total, le type ou la facture corrigée ont pu changer : chacune se
          # recalcule sur ce qui la règle, jamais d'après l'ancien état.
          [@invoice, @invoice.credited_invoice, ancienne_corrigee].compact.uniq.each do |facture|
            RefreshPayment.new(sales_invoice: facture).run!
          end
        end
      end

      @invoice.reload
    end

    def repasser?
      return false unless @invoice.on_issue? && @invoice.posted?

      (@invoice.changed & ACCOUNTING_ATTRIBUTES).any? || @attributes.key?("sales_invoice_lines_attributes")
    end
  end
end
