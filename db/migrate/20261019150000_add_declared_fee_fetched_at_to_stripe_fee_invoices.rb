# Le montant d'un justificatif Stripe peut venir de Stripe lui-même
# (`Stripe::PrefillFeeInvoices`, Michael 2026-10-19) : Stripe n'expose pas le PDF
# de sa facture de frais par l'API, mais le total des frais du mois, oui. Cette
# date dit que le montant a été relevé chez Stripe et pas lu sur le PDF ; une
# saisie à la main l'efface.
class AddDeclaredFeeFetchedAtToStripeFeeInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :stripe_fee_invoices, :declared_fee_fetched_at, :datetime
  end
end
