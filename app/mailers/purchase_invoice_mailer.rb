# Emails INTERNES des factures d'achat (epic #240, phase 3).
#
# Aucun de ces messages ne part vers un fournisseur : les membres du pôle qui
# doit dire oui, et la coordination comptable quand ça coince. C'est pourquoi
# ils ne sont pas journalisés dans `SentEmail`, réservé aux emails clients.
class PurchaseInvoiceMailer < ApplicationMailer
  # Une facture attend l'aval du pôle. Le lien porte un jeton à portée unique :
  # répondre ne demande pas de compte, parce qu'un sourcier qui devrait d'abord
  # se souvenir d'un mot de passe ne répond pas — et le blocage redevient
  # invisible, ce que toute cette phase cherche à éviter.
  def validation_requested(invoice, recipient)
    prepare(invoice, recipient)
    mail(to: recipient, subject: "À valider — #{subject_tail}")
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
