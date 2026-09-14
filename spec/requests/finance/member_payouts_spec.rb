require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #246, phase 2 — les écrans du paiement des cuisiniers.
RSpec.describe "Finances — payer un cuisinier", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:dettes) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let!(:zoe) { Human.create!(name: "Zoé Renard", email: "zoe@les4sources.be", iban: "BE68539007547034") }
  let!(:lino) { Human.create!(name: "Lino Bastin") }
  let!(:compte_zoe) { MemberAccount.for_human!(zoe) }
  let!(:compte_lino) { MemberAccount.for_human!(lino) }

  before do
    sign_in user
    compte_zoe.account_entries.create!(entry_date: Date.new(2026, 6, 12), kind: "cook_fee", flow: "meal",
                                       label: "Batch cooking du 12/06", amount_cents: -1_750)
    compte_lino.account_entries.create!(entry_date: Date.new(2026, 6, 12), kind: "cook_fee", flow: "meal",
                                        label: "Batch cooking du 12/06", amount_cents: -700)
  end

  describe "la liste « Cuisiniers à payer »" do
    it "montre la dette, l'IBAN et la communication" do
      get finance_batch_cooking_sessions_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cuisiniers à payer")
      expect(response.body).to include("Zoé Renard")
      expect(response.body).to include("BE68539007547034")
      expect(response.body).to include(compte_zoe.code)
      expect(response.body).to include("24,50")
    end

    # Masquer un compte sans IBAN ferait disparaître la dette parce qu'il manque
    # une coordonnée.
    it "signale un compte sans IBAN sans le cacher" do
      get finance_batch_cooking_sessions_path

      expect(response.body).to include("Lino Bastin")
      expect(response.body).to include("IBAN manquant")
      expect(response.body).to include(edit_human_path(lino))
    end

    it "disparaît quand plus personne n'attend d'argent" do
      AccountEntry.destroy_all

      get finance_batch_cooking_sessions_path

      expect(response.body).not_to include("Cuisiniers à payer")
    end
  end

  describe "la proposition sur « À affecter »" do
    it "propose de solder le compte quand le montant correspond" do
      build_cash_entry(compte_bancaire, amount_cents: -1_750, label: "Virement sortant")

      get finance_unallocated_cash_entries_path

      expect(response.body).to include("Virement à Zoé Renard")
      expect(response.body).to include("Solder son compte")
    end

    it "ne propose rien sur une ligne entrante" do
      build_cash_entry(compte_bancaire, amount_cents: 1_750, label: "Virement entrant")

      get finance_unallocated_cash_entries_path

      expect(response.body).not_to include("Solder son compte")
    end
  end

  describe "POST /finance/cash_entries/:id/payout" do
    it "solde le compte et affecte la ligne" do
      entry = build_cash_entry(compte_bancaire, amount_cents: -1_750, entry_date: Date.new(2026, 6, 20),
                               label: "Virement Zoé")

      post payout_finance_cash_entry_path(entry, member_account_id: compte_zoe.id)

      expect(compte_zoe.reload.balance_cents).to eq(0)
      expect(entry.reload.cash_allocations.first.general_account).to eq(dettes)
      expect(response).to redirect_to(finance_unallocated_cash_entries_path)
    end

    it "refuse un virement plus gros que le solde dû" do
      entry = build_cash_entry(compte_bancaire, amount_cents: -9_900, label: "Trop gros")

      post payout_finance_cash_entry_path(entry, member_account_id: compte_zoe.id, amount: "99,00")

      expect(compte_zoe.reload.balance_cents).to eq(-1_750)
      expect(entry.reload.cash_allocations).to be_empty
      follow_redirect!
      expect(response.body).to include("n&#39;attend que").or include("n'attend que")
    end
  end

  describe "un virement partiel" do
    it "ne solde que ce qu'on vire" do
      entry = build_cash_entry(compte_bancaire, amount_cents: -1_000, label: "Acompte")

      post payout_finance_cash_entry_path(entry, member_account_id: compte_zoe.id, amount: "10,00")

      expect(compte_zoe.reload.balance_cents).to eq(-750)
    end
  end

  describe "la fiche humain" do
    it "accepte un IBAN et son titulaire" do
      patch human_path(lino), params: { human: { name: "Lino Bastin", iban: "be62 5100 0754 7061",
                                                 iban_holder_name: "Marie Bastin" } }

      expect(lino.reload.iban).to eq("BE62510007547061")
      expect(lino.iban_holder).to eq("Marie Bastin")
    end

    it "refuse un IBAN qui n'en est pas un" do
      patch human_path(lino), params: { human: { name: "Lino Bastin", iban: "PAS-UN-IBAN" } }

      expect(lino.reload.iban).to be_nil
    end
  end
end
