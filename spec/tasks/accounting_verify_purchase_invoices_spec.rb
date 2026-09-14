require "rails_helper"
require "rake"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 2 — le filet des factures d'achat.
RSpec.describe "accounting:verify_purchase_invoices" do
  include FinanceBuilders

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:fournisseur) { ThirdParty.create!(name: "Antargaz", kind: "supplier") }

  def run_task
    original = $stdout
    $stdout = StringIO.new.tap { |io| io.set_encoding(Encoding::UTF_8) }
    Rake::Task["accounting:verify_purchase_invoices"].reenable
    Rake::Task["accounting:verify_purchase_invoices"].invoke
    :ok
  rescue SystemExit
    :exit_1
  ensure
    $stdout = original
  end

  def facture(total: 12_000, number: "F-1")
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: fournisseur, number: number,
                                issued_on: Date.new(2026, 6, 1), total_cents: total)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
    f.reload
  end

  it "sort vide quand il n'y a rien" do
    expect(run_task).to eq(:ok)
  end

  it "sort vide sur une facture à traiter, même sans ventilation" do
    PurchaseInvoice.create!(legal_entity: entity, third_party: fournisseur, number: "F-9",
                            issued_on: Date.new(2026, 6, 1), total_cents: 5_000)

    expect(run_task).to eq(:ok)
  end

  it "sort vide sur une facture comptabilisée" do
    PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!

    expect(run_task).to eq(:ok)
  end

  it "crie sur une facture « à payer » sans écriture" do
    f = facture
    f.update_column(:status, "to_pay")

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand les lignes ne couvrent plus le total" do
    f = PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!
    f.purchase_invoice_lines.first.update_column(:amount_cents, 5_000)

    expect(run_task).to eq(:exit_1)
  end

  it "crie sur une facture payée que rien ne rapproche" do
    f = PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!
    f.update_columns(status: "paid", paid_on: Date.current)

    expect(run_task).to eq(:exit_1)
  end
end
