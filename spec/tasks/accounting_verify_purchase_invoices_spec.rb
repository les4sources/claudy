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

  # --- Phase 4 : le filet s'étend aux ALLOCATIONS -------------------------
  describe "les allocations qui la paient (phase 4)" do
    let!(:caisse) { build_cash_account(entity, banque) }

    def allocation_sur(invoice, account:, amount_cents:)
      entry = build_cash_entry(caisse, amount_cents: -amount_cents, label: "Virement")
      entry.cash_allocations.create!(general_account: account, legal_entity: entity,
                                     third_party: fournisseur, document: invoice,
                                     amount_cents: -amount_cents)
    end

    it "sort vide quand une facture est rapprochée sur le 440000 pour son montant" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!
      allocation_sur(f, account: fournisseurs, amount_cents: f.total_cents)

      expect(f.reload).to be_paid
      expect(run_task).to eq(:ok)
    end

    # Rapprocher sur la CHARGE compterait la dépense deux fois : une fois au
    # journal des achats, une fois sur la ligne bancaire.
    it "crie quand le rapprochement se fait sur un autre compte que le 440000" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!
      allocation_sur(f, account: charges, amount_cents: f.total_cents)

      expect(run_task).to eq(:exit_1)
    end

    it "crie sur une facture surpayée" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!
      allocation_sur(f, account: fournisseurs, amount_cents: f.total_cents + 1_000)

      expect(run_task).to eq(:exit_1)
    end

    # Un état qui ne sait que monter est un état faux : une facture couverte qui
    # resterait « à payer » remonterait sur la file et serait payée deux fois.
    it "crie sur une facture entièrement rapprochée restée « à payer »" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!
      allocation_sur(f, account: fournisseurs, amount_cents: f.total_cents)
      f.reload.update_columns(status: "to_pay", paid_on: nil)

      expect(run_task).to eq(:exit_1)
    end

    it "crie sur une facture payée sans date de paiement" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!
      allocation_sur(f, account: fournisseurs, amount_cents: f.total_cents)
      f.reload.update_columns(paid_on: nil)

      expect(run_task).to eq(:exit_1)
    end

    it "sort vide sur un paiement PARTIEL : la facture reste « à payer »" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!
      allocation_sur(f, account: fournisseurs, amount_cents: 5_000)

      expect(f.reload).to be_to_pay
      expect(run_task).to eq(:ok)
    end
  end
end
