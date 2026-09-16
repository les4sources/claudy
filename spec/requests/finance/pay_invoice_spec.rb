require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 4 — payer une facture depuis « À affecter » et depuis la fiche.
RSpec.describe "Payer une facture d'achat", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-pay@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque_compte) { build_general_account(code: "550000", name: "Banque") }
  let!(:caisse_compte) { build_general_account(code: "570000", name: "Caisse") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:banque) { build_cash_account(entity, banque_compte) }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", iban: "BE68539007547034") }

  before { sign_in user }

  let(:facture) do
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: antargaz, number: "F-1",
                               issued_on: Date.new(2026, 6, 1), total_cents: 12_000)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: 12_000)
    PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
  end

  describe "l'écran « À affecter »" do
    it "propose la facture sur une ligne sortante du même montant, avec sa raison" do
      facture
      build_cash_entry(banque, amount_cents: -12_000, label: "Virement Antargaz")

      get finance_unallocated_cash_entries_path

      expect(response.body).to include("Paiement de Facture Antargaz · F-1")
      expect(response.body).to include("Payer cette facture")
      expect(response.body).to include("% de confiance")
    end

    # L'INVARIANT B4 : afficher une proposition n'écrit rien. C'est le clic qui écrit.
    it "n'écrit aucune allocation en affichant la proposition" do
      facture
      build_cash_entry(banque, amount_cents: -12_000, label: "Virement Antargaz")

      expect { get finance_unallocated_cash_entries_path }.not_to change(CashAllocation, :count)
      expect(facture.reload).to be_to_pay
    end

    it "ne propose rien sur une ligne ENTRANTE" do
      facture
      build_cash_entry(banque, amount_cents: 12_000, label: "Recette")

      get finance_unallocated_cash_entries_path

      expect(response.body).not_to include("Payer cette facture")
    end
  end

  describe "POST pay_invoice" do
    it "affecte la ligne sur la facture et la fait passer « payée »" do
      entry = build_cash_entry(banque, amount_cents: -12_000, label: "Virement Antargaz")

      post pay_invoice_finance_cash_entry_path(entry, purchase_invoice_id: facture.id)

      expect(response).to redirect_to(finance_unallocated_cash_entries_path)
      expect(facture.reload).to be_paid
      expect(entry.reload.cash_allocations.sole.document).to eq(facture)
    end

    it "refuse poliment une ligne entrante, sans rien écrire" do
      entry = build_cash_entry(banque, amount_cents: 12_000, label: "Recette")

      expect { post pay_invoice_finance_cash_entry_path(entry, purchase_invoice_id: facture.id) }
        .not_to change(CashAllocation, :count)

      expect(response).to redirect_to(finance_cash_entry_path(entry))
      expect(flash[:alert]).to include("SORTANTE")
    end
  end

  describe "POST pay_in_cash depuis la fiche" do
    let!(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse épicerie", kind: "cash") }

    it "crée la sortie de caisse et fait passer la facture « payée »" do
      expect { post pay_in_cash_finance_purchase_invoice_path(facture, paid_on: "2026-06-20") }
        .to change(CashEntry, :count).by(1)

      expect(facture.reload).to be_paid
      expect(CashEntry.order(:id).last.cash_account).to eq(caisse)
    end

    it "remonte le motif quand aucune caisse n'existe" do
      caisse.update!(active: false)

      post pay_in_cash_finance_purchase_invoice_path(facture)

      expect(response).to redirect_to(finance_purchase_invoice_path(facture))
      expect(flash[:alert]).to include("Aucune caisse active")
    end

    it "propose le règlement en espèces sur la fiche d'une facture à payer" do
      get finance_purchase_invoice_path(facture)

      expect(response.body).to include("Payée en caisse")
      expect(response.body).to include("BE68539007547034")
      expect(response.body).to include("Copier l'IBAN")
    end

    # « Compte de caisse à choisir » : quand l'entité en a plusieurs, prendre la
    # première venue serait un choix muet — la caisse épicerie ne se confond pas
    # avec celle du bar.
    it "laisse choisir la caisse quand l'entité en a plusieurs" do
      bar = build_cash_account(entity, caisse_compte, name: "Caisse bar", kind: "cash")

      get finance_purchase_invoice_path(facture)
      expect(response.body).to include("Caisse bar", "Caisse épicerie")

      post pay_in_cash_finance_purchase_invoice_path(facture, cash_account_id: bar.id)

      expect(CashEntry.order(:id).last.cash_account).to eq(bar)
    end

    it "ne le propose plus une fois la facture payée" do
      post pay_in_cash_finance_purchase_invoice_path(facture)
      get finance_purchase_invoice_path(facture.reload)

      expect(response.body).not_to include("Payée en caisse")
    end
  end
end
