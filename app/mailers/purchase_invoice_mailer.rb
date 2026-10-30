# Emails INTERNES des factures d'achat (epic #240, phase 3).
#
# Aucun de ces messages ne part vers un fournisseur : les membres du pôle qui
# doit dire oui, et la coordination comptable quand ça coince. C'est pourquoi
# ils ne sont pas journalisés dans `SentEmail`, réservé aux emails clients.
class PurchaseInvoiceMailer < ApplicationMailer
  # Le récapitulatif du lundi (`PurchaseInvoices::ValidationDigest`) : toutes
  # les factures qui attendent l'aval des pôles de ce membre, en un email.
  # Chaque facture porte son lien à jeton : répondre ne demande pas de compte,
  # parce qu'un sourcier qui devrait d'abord se souvenir d'un mot de passe ne
  # répond pas — et le blocage redevient invisible.
  def validation_digest(human, invoices)
    @human     = human
    @invoices  = invoices
    @link_host = ENV.fetch("APPLICATION_HOST", "app.les4sources.be")
    @total     = Money.new(invoices.sum(&:total_cents), "EUR")
    @list_url  = finance_purchase_invoices_url(status: "to_validate", host: @link_host)
    count = invoices.size
    mail(to: human.email,
         subject: "#{count} facture#{'s' if count > 1} à valider — #{@total.format}")
  end

  # Le pôle a refusé. Ça part à la coordination comptable, pour qu'elle reprenne
  # la main auprès du fournisseur tout de suite.
  def disputed(invoice, recipient)
    prepare(invoice, recipient)
    mail(to: recipient, subject: "Facture contestée — #{subject_tail}")
  end

  private

  def prepare(invoice, recipient)
    @invoice   = invoice
    @recipient = recipient
    @lines     = invoice.purchase_invoice_lines.includes(:general_account, :team)
    @link_host = ENV.fetch("APPLICATION_HOST", "app.les4sources.be")
    @token     = invoice.validation_token
    @admin_url = finance_purchase_invoice_url(invoice, host: @link_host)
  end

  def subject_tail
    montant = Money.new(@invoice.total_cents, "EUR").format
    [@invoice.third_party&.name.presence || "Fournisseur", montant].join(" — ")
  end
end
