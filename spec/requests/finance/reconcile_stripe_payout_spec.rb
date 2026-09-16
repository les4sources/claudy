require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 2 — rapprocher un versement Stripe depuis « À affecter ».
RSpec.describe "Rapprocher un versement Stripe", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-stripe-rec@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque_compte) { build_general_account(code: "550000", name: "Banque") }
  let!(:stripe_compte) { build_general_account(code: "551000", name: "Stripe") }
  let!(:transferts) { build_general_account(code: "580000", name: "Virements internes", klass: 5, nature: "asset") }
  let!(:banque) { build_cash_account(entity, banque_compte) }
  let!(:compte) do
    CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                        general_account: stripe_compte, stripe_account_key: "tranche_de_vie",
                        stripe_mode: "ledger")
  end

  before { sign_in user }

  let(:versement) do
    StripePayout.create!(account_key: "tranche_de_vie", cash_account: compte, stripe_id: "po_1",
                         amount_cents: 126_900, arrival_date: Date.new(2026, 6, 15))
  end

  def ligne(amount_cents: 126_900)
    build_cash_entry(banque, amount_cents: amount_cents, entry_date: Date.new(2026, 6, 15),
                     label: "STRIPE PAYOUT")
  end

  describe "l'écran « À affecter »" do
    it "propose le versement sur la ligne bancaire du même montant" do
      versement
      ligne

      get finance_unallocated_cash_entries_path

      expect(response.body).to include("Versement Stripe")
      expect(response.body).to include("Rapprocher ce versement")
      expect(response.body).to include("% de confiance")
    end

    # L'invariant B4 : afficher une proposition n'écrit rien.
    it "n'écrit aucune allocation en affichant la proposition" do
      versement
      ligne

      expect { get finance_unallocated_cash_entries_path }.not_to change(CashAllocation, :count)
    end

    # Un compte en mode « par versement » demanderait une ventilation algébrique
    # que `CashAllocation` refuse : on le DIT plutôt que d'offrir un bouton qui
    # échouerait.
    it "n'offre pas le bouton pour un compte en mode par versement" do
      compte.update!(stripe_mode: "per_payout")
      versement
      ligne

      get finance_unallocated_cash_entries_path

      expect(response.body).to include("Versement Stripe")
      expect(response.body).not_to include("Rapprocher ce versement")
      expect(response.body).to include("à affecter à la main")
    end
  end

  describe "POST reconcile_payout" do
    it "affecte la ligne sur le 580000 avec le versement en document" do
      entry = ligne

      post reconcile_payout_finance_cash_entry_path(entry, stripe_payout_id: versement.id)

      expect(response).to redirect_to(finance_unallocated_cash_entries_path)
      allocation = entry.reload.cash_allocations.sole
      expect(allocation.general_account).to eq(transferts)
      expect(allocation.document).to eq(versement)
    end

    it "comptabilise la ligne devenue entièrement affectée" do
      entry = ligne

      post reconcile_payout_finance_cash_entry_path(entry, stripe_payout_id: versement.id)

      expect(entry.reload).to be_posted
    end

    it "refuse poliment un versement déjà rapproché, sans rien écrire" do
      entry = ligne
      post reconcile_payout_finance_cash_entry_path(entry, stripe_payout_id: versement.id)
      autre = ligne

      expect { post reconcile_payout_finance_cash_entry_path(autre, stripe_payout_id: versement.id) }
        .not_to change(CashAllocation, :count)

      expect(response).to redirect_to(finance_cash_entry_path(autre))
      expect(flash[:alert]).to include("déjà rapproché")
    end

    it "refuse un montant qui ne correspond pas" do
      entry = ligne(amount_cents: 100_000)

      post reconcile_payout_finance_cash_entry_path(entry, stripe_payout_id: versement.id)

      expect(flash[:alert]).to include("pas le même mouvement")
    end
  end
end
