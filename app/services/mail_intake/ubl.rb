module MailIntake
  # Lit une facture électronique UBL (Peppol BIS 3) — messagerie, 2026-09-30.
  #
  # Depuis 2026, les factures entre entreprises belges voyagent en UBL, et
  # OkiOki en renvoie une copie sur compta@. Là où le PDF oblige à DEVINER
  # (des montants trouvés par regex, puis choisis par Jev), l'UBL DIT : le
  # fournisseur, sa TVA, son IBAN, le total, la TVA par taux, ce qui reste à
  # payer — et embarque le PDF lui-même. Aucune IA ici.
  #
  # Sécurité : le XML vient de l'extérieur. Nokogiri est appelé en `nonet`
  # (aucun accès réseau) et sans DTD ni entités externes, la configuration par
  # défaut de Nokogiri que ce fichier ne relâche jamais.
  class Ubl
    MAX_EMBEDDED_BYTES = 15.megabytes

    Party = Data.define(:name, :vat, :iban, :email)
    TaxLine = Data.define(:percent, :taxable_cents, :tax_cents) do
      def total_cents = taxable_cents + tax_cents
    end
    Embedded = Data.define(:filename, :content_type, :bytes)

    def self.ubl?(xml)
      root = parse(xml)&.root
      root.present? && %w[Invoice CreditNote].include?(root.name) &&
        root.namespace&.href.to_s.include?("oasis:names:specification:ubl")
    end

    def self.parse(xml)
      Nokogiri::XML(xml.to_s, &:nonet)
    rescue Nokogiri::XML::SyntaxError
      nil
    end

    def initialize(xml)
      @doc = self.class.parse(xml) or raise ArgumentError, "XML illisible"
      @doc.remove_namespaces!
    end

    def credit_note? = @doc.root.name == "CreditNote" || text("/*/InvoiceTypeCode") == "381"

    def number = text("/*/ID")

    def issued_on = date(text("/*/IssueDate"))

    def due_on = date(text("/*/DueDate") || text("//PaymentMeans/PaymentDueDate"))

    def supplier = party("AccountingSupplierParty")

    def customer = party("AccountingCustomerParty")

    def total_cents = cents(text("//LegalMonetaryTotal/TaxInclusiveAmount"))

    def prepaid_cents = cents(text("//LegalMonetaryTotal/PrepaidAmount"))

    def payable_cents = cents(text("//LegalMonetaryTotal/PayableAmount"))

    # Payée d'avance : l'UBL le dit quand il ne reste rien à payer sur un total
    # qui n'est pas nul (un ticket de caisse transmis en facture, typiquement).
    def fully_prepaid? = total_cents.to_i.positive? && payable_cents.to_i.zero?

    def payment_reference = text("//PaymentMeans/PaymentID")

    def tax_lines
      @doc.xpath("/*/TaxTotal/TaxSubtotal").map do |subtotal|
        TaxLine.new(percent: subtotal.at_xpath(".//Percent")&.text.to_f,
                    taxable_cents: cents(subtotal.at_xpath("TaxableAmount")&.text).to_i,
                    tax_cents: cents(subtotal.at_xpath("TaxAmount")&.text).to_i)
      end
    end

    # Le PDF que le fournisseur a joint à sa facture électronique — celui que
    # l'on consulte et que l'on garde comme pièce.
    def embedded_pdf
      node = @doc.xpath("//EmbeddedDocumentBinaryObject").find { |n| n["mimeCode"].to_s.include?("pdf") }
      return nil if node.nil? || node.text.bytesize > MAX_EMBEDDED_BYTES * 4 / 3 + 1024

      Embedded.new(filename: node["filename"].presence || "#{number.to_s.parameterize.presence || 'facture'}.pdf",
                   content_type: "application/pdf", bytes: Base64.decode64(node.text))
    end

    private

    def party(role)
      base = "//#{role}/Party"
      Party.new(
        name: text("#{base}/PartyName/Name") || text("#{base}/PartyLegalEntity/RegistrationName"),
        vat: text("#{base}/PartyTaxScheme/CompanyID") || text("#{base}/PartyLegalEntity/CompanyID"),
        iban: role == "AccountingSupplierParty" ? text("//PaymentMeans/PayeeFinancialAccount/ID")&.gsub(/\s/, "") : nil,
        email: text("#{base}/Contact/ElectronicMail")
      )
    end

    def text(xpath) = @doc.at_xpath(xpath)&.text&.strip.presence

    def date(raw)
      raw && Date.iso8601(raw)
    rescue Date::Error
      nil
    end

    def cents(raw)
      raw && (BigDecimal(raw) * 100).round.to_i
    rescue ArgumentError
      nil
    end
  end
end
