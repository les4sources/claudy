require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La TVA d'une facture d'achat à la passation : récupérée par une entité
# assujettie qui a ouvert le 411000, sinon comprise dans la charge.
RSpec.describe Accounting::PostPurchaseInvoice do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:boulangerie) { build_general_account(code: "600003", name: "Boulangerie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:tva) { build_general_account(code: "411000", name: "TVA à récupérer", klass: 4, nature: "asset") }
  let!(:domaine) { ThirdParty.create!(name: "SPRL Domaine d'Ahinvaux", kind: "supplier") }

  def facture
    invoice = PurchaseInvoice.new(legal_entity: entity, third_party: domaine, number: "2026-014",
                                  issued_on: Date.new(2026, 10, 15), total_cents: 143_882)
    invoice.purchase_invoice_lines.build(general_account: boulangerie, net_cents: 118_911, vat_rate: 21)
    invoice.save!
    invoice
  end

  def debits(entry)
    entry.journal_lines.select { |l| l.debit_cents.positive? }.to_h { |l| [l.general_account.code, l.debit_cents] }
  end

  it "met la TVA dans la charge pour une entité exemptée" do
    entry = described_class.new(purchase_invoice: facture).run!

    expect(debits(entry)).to eq("600003" => 143_882)
  end

  it "envoie la TVA au 411000 pour une entité assujettie" do
    entity.update!(vat_regime: "subject")

    entry = described_class.new(purchase_invoice: facture).run!

    expect(debits(entry)).to eq("600003" => 118_911, "411000" => 24_971)
    expect(entry.journal_lines.sum(&:credit_cents)).to eq(143_882)
  end

  it "garde la TVA dans la charge tant que le 411000 est désactivé" do
    entity.update!(vat_regime: "subject")
    tva.update!(active: false)

    entry = described_class.new(purchase_invoice: facture).run!

    expect(debits(entry)).to eq("600003" => 143_882)
  end
end
