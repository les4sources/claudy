module PurchaseInvoices
  # Une facture d'achat encodée depuis une pièce de la boite de réception
  # `compta@` (messagerie, phase 1).
  #
  # Sorti de `PurchaseInvoicesController` le 2026-10-13 pour que le connecteur
  # Claude encode une pièce du mail exactement comme l'écran : même
  # préremplissage, même pièce justificative (le PDF du mail, déjà en base),
  # même classement du mail et de ses jumeaux.
  class FromMailAttachment
    attr_reader :attachment

    def initialize(attachment)
      @attachment = attachment
    end

    # La proposition préremplit, elle ne décide pas : l'humain relit tout avant
    # d'enregistrer. Un fournisseur désactivé depuis n'est pas proposé.
    def prefill(invoice)
      supplier_id = attachment.proposed(:third_party_id) || supplier_matching_vat(attachment.proposed(:supplier_vat))
      invoice.third_party_id = supplier_id if supplier_id && ThirdParty.actives.suppliers.exists?(id: supplier_id)
      entity_id = attachment.proposed(:legal_entity_id)
      invoice.legal_entity_id = entity_id if entity_id && LegalEntity.actives.exists?(id: entity_id)
      %i[number total_cents issued_on due_on payment_reference].each do |field|
        value = attachment.proposed(field)
        invoice.public_send("#{field}=", value) if value.present?
      end
      prefill_vat_lines(invoice, attachment.proposed(:vat_lines))
      invoice.notes = "Payée d'avance selon la facture électronique (UBL)." if attachment.proposed(:fully_prepaid)
      invoice.document.attach(attachment.file.blob)
    end

    # La pièce du mail devient la pièce justificative. Le sha256 est celui
    # calculé à l'arrivée du mail.
    def attach_document(invoice)
      invoice.document.attach(attachment.file.blob)
      invoice.pdf_sha256 = attachment.sha256
    end

    def settle!(invoice, user)
      attachment.update!(purchase_invoice: invoice)
      attachment.mail_message.settle_if_complete!(user)
      settle_twin_attachments(invoice, user)
    end

    private

    # Une facture électronique donne la TVA par taux : une ligne de ventilation
    # par taux, au montant TVAC, dont il ne reste qu'à choisir compte et pôle.
    def prefill_vat_lines(invoice, lines)
      Array(lines).each do |line|
        # Un taux déclaré à 0,00 € (3 PETITS POIDS annonce un 0 % vide) ferait
        # une ligne vide, que la validation refuse.
        next if line["total_cents"].to_i.zero?

        percent = line["percent"].to_f
        label = "TVA #{percent == percent.round ? percent.round : percent.to_s.tr('.', ',')} %"
        invoice.purchase_invoice_lines.build(amount_cents: line["total_cents"], label: label)
      end
    end

    # Un fournisseur créé APRÈS la lecture du mail (depuis une facture sœur,
    # typiquement) se retrouve par la TVA lue dans la pièce.
    def supplier_matching_vat(raw)
      vat = MailIntake::InvoiceCandidates.normalize_vat(raw)
      return nil unless vat

      ThirdParty.actives.suppliers.find { |t| MailIntake::InvoiceCandidates.normalize_vat(t.vat_number) == vat }&.id
    end

    # OkiOki envoie deux mails pour une même facture — le PDF, puis l'UBL. Les
    # pièces encore en file qui désignent CETTE facture (même fichier, ou même
    # numéro chez le même fournisseur) sont classées avec elle : une facture
    # encodée ne doit pas en laisser une seconde à encoder.
    def settle_twin_attachments(invoice, user)
      MailAttachment.where(purchase_invoice_id: nil).joins(:mail_message)
                    .merge(MailMessage.pending).includes(:mail_message).find_each do |twin|
        next unless twin.invoice_like? && twin.existing_invoice == invoice

        twin.update!(purchase_invoice: invoice)
        twin.mail_message.settle_if_complete!(user)
      end
    end
  end
end
