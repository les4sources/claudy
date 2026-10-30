module Notifications
  # « Une facture attend l'aval de ton pôle » (epic #242, phase 3).
  #
  # Aux membres du pôle QUI ONT UN COMPTE, et sans copie par email : l'email,
  # c'est le récapitulatif du lundi (`PurchaseInvoices::ValidationDigest`), qui
  # va à tous ceux qui ont une adresse. Une facture = un email, c'était trop
  # (Michael, 2026-10-30).
  class PurchaseInvoiceToValidate
    def initialize(invoice)
      @invoice = invoice
    end

    def self.call(invoice) = new(invoice).call

    def call
      recipients = @invoice.validation_users.to_a
      return [] if recipients.empty?

      Notify.broadcast(
        recipients: recipients,
        kind: "purchase_invoice_to_validate",
        title: title,
        body: body,
        url: @invoice.comment_path,
        notifiable: @invoice,
        email: false
      )
    end

    private

    def title
      montant = Money.new(@invoice.total_cents, "EUR").format
      fournisseur = @invoice.third_party&.name.presence || "Fournisseur"
      "Facture à valider — #{fournisseur}, #{montant}"
    end

    def body
      morceaux = ["Tant que personne n'a répondu, elle n'est pas payable."]
      morceaux << "Échéance le #{I18n.l(@invoice.due_on, format: :long)}." if @invoice.due_on.present?
      morceaux.join(" ")
    end
  end
end
