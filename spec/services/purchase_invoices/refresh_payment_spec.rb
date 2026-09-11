require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, décision 4 — le paiement d'une facture est un RAPPROCHEMENT. On ne
# coche pas « payée » : on constate que les lignes de trésorerie la couvrent.
RSpec.describe PurchaseInvoices::RefreshPayment do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte) { build_cash_account(entity, banque) }
  let!(:fournisseur) { ThirdParty.create!(name: "Antargaz", kind: "supplier") }

  let(:invoice) do
    facture = PurchaseInvoice.create!(legal_entity: entity, third_party: fournisseur, number: "F-1",
                                      issued_on: Date.new(2026, 6, 1), total_cents: 12_000)
    facture.purchase_invoice_lines.create!(general_account: charges, amount_cents: 12_000)
    PurchaseInvoices::Advance.new(purchase_invoice: facture.reload).submit!
  end

  def paie(cents, day: Date.new(2026, 6, 20))
    entry = build_cash_entry(compte, amount_cents: -cents, entry_date: day, label: "Virement Antargaz")
    entry.cash_allocations.create!(general_account: fournisseurs, legal_entity: entity,
                                   third_party: fournisseur, document: invoice, amount_cents: -cents)
    entry
  end

  it "passe la facture en payée quand le rapprochement la couvre" do
    expect(invoice.status).to eq("to_pay")

    paie(12_000)

    expect(invoice.reload.status).to eq("paid")
    expect(invoice.paid_on).to eq(Date.new(2026, 6, 20))
  end

  it "la laisse à payer sur un rapprochement partiel" do
    paie(5_000)

    expect(invoice.reload.status).to eq("to_pay")
    expect(invoice.remaining_cents).to eq(7_000)
  end

  it "additionne deux paiements partiels" do
    paie(5_000, day: Date.new(2026, 6, 10))
    paie(7_000, day: Date.new(2026, 6, 20))

    expect(invoice.reload.status).to eq("paid")
    expect(invoice.paid_on).to eq(Date.new(2026, 6, 20))
  end

  # Un état qui ne sait que monter est un état faux : défaire l'affectation doit
  # ramener la facture à « À payer ».
  it "redevient à payer quand on défait l'affectation" do
    entry = paie(12_000)
    expect(invoice.reload.status).to eq("paid")

    entry.cash_allocations.destroy_all

    expect(invoice.reload.status).to eq("to_pay")
    expect(invoice.paid_on).to be_nil
  end

  it "ne touche pas une facture encore en traitement" do
    autre = PurchaseInvoice.create!(legal_entity: entity, third_party: fournisseur, number: "F-2",
                                    issued_on: Date.new(2026, 6, 1), total_cents: 3_000)

    described_class.new(purchase_invoice: autre).run!

    expect(autre.reload.status).to eq("to_process")
  end
end
