module SalesInvoices
  # L'enregistrement d'une facture de vente depuis la file Facturation
  # (epic #240, phase 6).
  #
  # Deux gestes qui doivent tomber ENSEMBLE : la facture et son lien vers ce
  # qu'elle facture, d'une part ; le passage du réservable en « facture
  # envoyée », d'autre part. C'est ce dernier qui fait sortir la ligne de la
  # file — une facture enregistrée sans lui laisserait le travail à refaire, et
  # un réservable marqué envoyé sans facture ferait disparaître la ligne sans
  # rien garder.
  #
  # `invoice_status = "sent"` est POSÉ TEL QUEL, comme avant cette phase : la
  # file, son historique par année et ses compteurs continuent de fonctionner
  # sans rien savoir des factures.
  class Register < ServiceBase
    class AlreadyInvoiced < StandardError; end
    class UnknownSource < StandardError; end

    def initialize(source:, legal_entity:, number:, issued_on:, total_cents:,
                   customer: nil, notes: nil, document: nil, whodunnit: nil)
      @source = source
      @legal_entity = legal_entity
      @number = number.to_s.strip
      @issued_on = issued_on
      @total_cents = total_cents.to_i
      @customer = customer
      @notes = notes
      @document = document
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { source: "#{@source.class}##{@source&.id}" }) { register }
    def run! = register

    def invoice = @invoice

    private

    def register
      raise UnknownSource, "Impossible de facturer un #{@source.class}." unless facturable?

      if SalesInvoiceSource.exists?(source_type: @source.class.name, source_id: @source.id)
        raise AlreadyInvoiced,
              "#{@source.class.name} ##{@source.id} est déjà rattaché à une facture de vente."
      end

      PaperTrail.request(whodunnit: @whodunnit || "sales_invoice") do
        ApplicationRecord.transaction do
          @invoice = SalesInvoice.create!(
            legal_entity: @legal_entity,
            customer: @customer || @source.try(:customer),
            number: @number,
            issued_on: @issued_on,
            total_cents: @total_cents,
            status: "issued",
            notes: @notes
          )
          @invoice.document.attach(@document) if @document.present?
          @invoice.sales_invoice_sources.create!(source: @source)

          # La file continue de lire `invoice_status` : c'est ce qui sort la
          # ligne de « à fournir » et la range dans l'historique des envois.
          @source.update!(invoice_status: Invoicing::Queue::SENT)
        end
      end

      @invoice
    end

    def facturable?
      SalesInvoiceSource::SOURCE_TYPES.include?(@source.class.name) &&
        @source.respond_to?(:invoice_status)
    end
  end
end
