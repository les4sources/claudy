module MailIntake
  # Traduit une facture électronique UBL en proposition de facture d'achat,
  # dans le même vocabulaire que la lecture d'un PDF (`MailAttachment#proposal`),
  # mais avec la source « ubl » : rien n'y est deviné, tout est lu.
  #
  # Une UBL émise par une de NOS entités est une vente (les copies « [Sales] »
  # qu'OkiOki renvoie sur compta@) : elle ne propose pas de facture d'achat —
  # sauf quand le client est une autre de nos entités (voir `kind`).
  class UblProposal
    def initialize(ubl, from_address: nil)
      @ubl = ubl
      @from_address = from_address
    end

    def to_h
      supplier = @ubl.supplier
      proposal = {
        "kind" => ubl_value(kind),
        "number" => ubl_value(@ubl.number),
        "issued_on" => ubl_value(@ubl.issued_on&.iso8601),
        "due_on" => ubl_value(@ubl.due_on&.iso8601),
        "total_cents" => ubl_value(@ubl.total_cents),
        "legal_entity_id" => ubl_value(entity_for(@ubl.customer.vat)&.id),
        "third_party_id" => ubl_value(known_supplier(supplier)&.id),
        "supplier_name" => ubl_value(supplier.name),
        "supplier_vat" => ubl_value(supplier.vat),
        "supplier_iban" => ubl_value(IbanValidator.valid_iban?(supplier.iban.to_s) ? supplier.iban : nil),
        "payment_reference" => ubl_value(payment_reference),
        "prepaid_cents" => ubl_value(@ubl.prepaid_cents&.nonzero?),
        "payable_cents" => ubl_value(@ubl.payable_cents),
        "fully_prepaid" => ubl_value(@ubl.fully_prepaid? || nil),
        "vat_lines" => ubl_value(vat_lines.presence)
      }
      proposal.compact
    end

    private

    # Une communication structurée est normalisée (et écartée si sa clé de
    # contrôle est fausse) ; une communication libre est reprise telle quelle,
    # puisque c'est le fournisseur qui la demande.
    def payment_reference
      raw = @ubl.payment_reference
      return nil if raw.blank?
      return StructuredCommunication.normalize(raw) if raw.match?(%r{\A[\s\d+*/]+\z})

      raw
    end

    # Une facture d'une de nos structures à une AUTRE des nôtres (la SRL qui
    # facture la Fondation, Michael 2026-10-30) n'est pas qu'une vente : c'est
    # la dette de la structure cliente. La lire « vente » la faisait ignorer, et
    # la Fondation ne la voyait jamais dans « À payer » (2026-013, 5 519,87 €).
    def kind
      return "sales" if ours?(@ubl.supplier.vat) && !intra_group?

      @ubl.credit_note? ? "credit_note" : "invoice"
    end

    def intra_group?
      supplier = InvoiceCandidates.normalize_vat(@ubl.supplier.vat)
      customer = InvoiceCandidates.normalize_vat(@ubl.customer.vat)
      ours?(customer) && customer != supplier
    end

    def ours?(vat) = our_vats.include?(InvoiceCandidates.normalize_vat(vat))

    # Une ligne de ventilation par taux de TVA, au montant TVAC du taux : la
    # somme retombe exactement sur le total de la facture.
    def vat_lines
      @ubl.tax_lines.map do |line|
        { "percent" => line.percent, "taxable_cents" => line.taxable_cents, "tax_cents" => line.tax_cents,
          "total_cents" => line.total_cents }
      end
    end

    def entity_for(vat)
      normalized = InvoiceCandidates.normalize_vat(vat)
      normalized && LegalEntity.actives.find { |e| InvoiceCandidates.normalize_vat(e.vat_number) == normalized }
    end

    def known_supplier(party)
      vat = InvoiceCandidates.normalize_vat(party.vat)
      iban = InvoiceCandidates.normalize_iban(party.iban)
      suppliers = ThirdParty.actives.suppliers.to_a
      suppliers.find { |t| vat && InvoiceCandidates.normalize_vat(t.vat_number) == vat } ||
        suppliers.find { |t| iban && t.iban.present? && InvoiceCandidates.normalize_iban(t.iban) == iban }
    end

    def our_vats
      @our_vats ||= LegalEntity.all.filter_map { |e| InvoiceCandidates.normalize_vat(e.vat_number) }
    end

    def ubl_value(value) = value.nil? ? nil : { "value" => value, "source" => "ubl" }
  end
end
