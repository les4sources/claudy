module Finance
  # Les factures reçues sur compta@ qui ne sont pas encore encodées (Michael,
  # 2026-10-30). « À payer » ne lit que les factures d'achat : une facture
  # OkiOki restée dans la boîte de réception n'y apparaissait nulle part, même
  # échue et relancée (Ferme de Grange, 742,87 €).
  #
  # Une pièce compte si son mail est encore « à traiter », qu'elle ressemble à
  # une facture ou à une note de crédit, qu'elle a un montant lu, et qu'aucune
  # facture déjà encodée ne lui correspond. OkiOki envoie deux mails par
  # facture (le PDF, puis l'UBL) : les jumelles n'en font qu'une, l'UBL d'abord
  # puisque ses valeurs sont lues et non devinées.
  class UnencodedMailInvoices
    Piece = Data.define(:attachment, :legal_entity, :supplier_name, :number, :total_cents, :issued_on, :due_on) do
      def credit_note? = attachment.kind == "credit_note"

      # Une note de crédit diminue ce qu'on devra payer.
      def signed_cents = credit_note? ? -total_cents : total_cents

      def overdue?(on = Date.current) = !credit_note? && due_on.present? && due_on < on

      def mail_message = attachment.mail_message
    end

    def initialize(legal_entity: nil)
      @legal_entity = legal_entity
    end

    def pieces
      @pieces ||= candidates.map { |attachment| piece(attachment) }
                            .reject { |piece| @legal_entity && piece.legal_entity != @legal_entity }
                            .sort_by { |piece| [piece.due_on || Date.new(9999, 1, 1), piece.attachment.id] }
    end

    # Les factures seules : une note de crédit ne s'encode pas comme une facture
    # d'achat, et la soustraire ferait passer 5 factures pour presque rien.
    def total_cents = pieces.reject(&:credit_note?).sum(&:total_cents)

    private

    def candidates
      @candidates ||= MailAttachment.joins(:mail_message).merge(MailMessage.pending)
                                    .where(purchase_invoice_id: nil)
                                    .includes(:mail_message)
                                    .to_a
                                    .select { |a| a.invoice_like? && a.proposed(:total_cents).present? }
                                    .sort_by { |a| [a.from_ubl? ? 0 : 1, a.id] }
                                    .uniq { |a| twin_key(a) }
                                    .reject { |a| encoded?(a) }
    end

    def twin_key(attachment)
      number = attachment.proposed(:number).to_s.downcase.gsub(/[^a-z0-9]/, "")
      number.present? ? [number, attachment.proposed(:total_cents)] : [:piece, attachment.id]
    end

    # `existing_invoice` reconnaît la pièce par son fichier ou son numéro. Une
    # lecture qui a pris le numéro de TVA pour le numéro de facture (Orange,
    # encodée sous Voo) passe à côté : le même montant le même jour la désigne
    # encore — ici on ne fait que montrer, jamais rattacher.
    def encoded?(attachment)
      return true if attachment.existing_invoice

      issued_on = attachment.proposed(:issued_on)
      issued_on.present? &&
        PurchaseInvoice.exists?(total_cents: attachment.proposed(:total_cents), issued_on: issued_on)
    end

    def piece(attachment)
      Piece.new(attachment: attachment,
                legal_entity: entities[attachment.proposed(:legal_entity_id)],
                supplier_name: supplier_name(attachment),
                number: attachment.proposed(:number).presence,
                total_cents: attachment.proposed(:total_cents).to_i,
                issued_on: date(attachment.proposed(:issued_on)),
                due_on: date(attachment.proposed(:due_on)))
    end

    def supplier_name(attachment)
      suppliers[attachment.proposed(:third_party_id)]&.name ||
        attachment.proposed(:supplier_name).presence ||
        attachment.mail_message.sender_label
    end

    def entities = @entities ||= LegalEntity.all.index_by(&:id)

    def suppliers
      @suppliers ||= ThirdParty.where(id: candidates.filter_map { |a| a.proposed(:third_party_id) }).index_by(&:id)
    end

    def date(value)
      value.present? ? Date.iso8601(value.to_s) : nil
    rescue Date::Error
      nil
    end
  end
end
