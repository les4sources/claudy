require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #349 — encaisser le règlement d'un habitant depuis « À affecter ».
RSpec.describe "Finances — rapprocher un virement entrant", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4) }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let!(:bene) { Human.create!(name: "Bénédicte Lambert", email: "bene@les4sources.be") }
  let!(:compte) { MemberAccount.for_human!(bene) }

  let(:entry) do
    ligne = build_cash_entry(compte_bancaire, amount_cents: 7_500, entry_date: Date.new(2026, 9, 5),
                             label: "Virement Béné")
    ligne.update!(communication: compte.code, counterparty_name: "LAMBERT BENEDICTE")
    ligne
  end

  before do
    sign_in user
    compte.account_entries.create!(entry_date: Date.new(2026, 9, 1), kind: "recurring", flow: "charges",
                                   label: "Frais mensuels", amount_cents: 7_500)
  end

  describe "l'écran « À affecter »" do
    it "propose le compte débiteur avec sa raison et sa confiance" do
      entry

      get finance_unallocated_cash_entries_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Règlement de #{compte.name}")
      expect(response.body).to include("Enregistrer le règlement")
      expect(response.body).to include("95 % de confiance")
      # Le poste se choisit avant d'enregistrer, et il est présélectionné.
      expect(response.body).to include("Poste réglé")
    end

    it "ne propose rien quand plus personne ne doit rien" do
      entry
      compte.account_entries.destroy_all

      get finance_unallocated_cash_entries_path

      expect(response.body).not_to include("Enregistrer le règlement")
    end
  end

  describe "POST settle" do
    it "enregistre le règlement sur le poste choisi et redirige avec un notice" do
      post settle_finance_cash_entry_path(entry, member_account_id: compte.id, flow: "charges")

      expect(compte.reload.account_entries.where(kind: "settlement").sole.flow).to eq("charges")
      expect(flash[:notice]).to include("Charges")
    end

    it "enregistre le règlement et redirige avec un notice" do
      post settle_finance_cash_entry_path(entry, member_account_id: compte.id, flow: "charges")

      expect(response).to redirect_to(finance_unallocated_cash_entries_path)
      expect(flash[:notice]).to include(compte.name)
      expect(compte.reload.balance_cents).to eq(0)
      expect(entry.reload.cash_allocations.first.general_account).to eq(clients)
    end

    it "accepte un montant partiel" do
      post settle_finance_cash_entry_path(entry, member_account_id: compte.id, amount: "30,00", flow: "charges")

      expect(compte.reload.balance_cents).to eq(4_500)
    end

    # Le double clic, ou le retour-arrière puis un second clic. La contrainte
    # d'unicité empêche le doublon ; c'est au contrôleur de le DIRE plutôt que
    # de laisser remonter l'erreur Postgres en 500.
    it "le dit sans rien doubler quand le virement est déjà imputé" do
      post settle_finance_cash_entry_path(entry, member_account_id: compte.id, amount: "30,00", flow: "charges")
      post settle_finance_cash_entry_path(entry, member_account_id: compte.id, amount: "30,00", flow: "charges")

      expect(response).to redirect_to(finance_unallocated_cash_entries_path)
      expect(flash[:alert]).to include("déjà imputé")
      expect(compte.reload.balance_cents).to eq(4_500)
      expect(compte.account_settlements.count).to eq(1)
      expect(entry.reload.cash_allocations.count).to eq(1)
    end

    it "redirige avec une alerte quand le service refuse" do
      sortante = build_cash_entry(compte_bancaire, amount_cents: -7_500, label: "Virement émis")

      post settle_finance_cash_entry_path(sortante, member_account_id: compte.id)

      expect(response).to redirect_to(finance_cash_entry_path(sortante))
      expect(flash[:alert]).to include("ligne ENTRANTE")
      expect(compte.reload.balance_cents).to eq(7_500)
    end
  end
end
