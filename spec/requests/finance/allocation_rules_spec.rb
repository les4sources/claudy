require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

RSpec.describe "Finances > Rapprochement assisté", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let!(:energie) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:cash_account) { build_cash_account(entity, bank_account) }
  let!(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }

  before { sign_in user }

  describe "les règles" do
    it "crée une règle et recalcule les suggestions dans la foulée" do
      entry = build_cash_entry(cash_account, amount_cents: -12_000, label: "Facture")
      entry.update!(counterparty_name: "ENGIE")

      expect {
        post finance_allocation_rules_path,
             params: { allocation_rule: { label: "Énergie", counterparty_name_contains: "ENGIE",
                                          general_account_id: energie.id, legal_entity_id: entity.id,
                                          team_id: technique.id, confidence: 90, position: 1 } }
      }.to change { AllocationSuggestion.count }.by(1)
    end

    it "refuse une règle sans critère plutôt que d'en créer une qui matche tout" do
      expect {
        post finance_allocation_rules_path,
             params: { allocation_rule: { label: "Fourre-tout", general_account_id: energie.id,
                                          legal_entity_id: entity.id } }
      }.not_to change { AllocationRule.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("s&#39;appliquerait à tout").or include("s'appliquerait à tout")
    end
  end

  describe "l'acceptation" do
    let!(:rule) do
      AllocationRule.create!(label: "Énergie", general_account: energie, legal_entity: entity,
                             team: technique, position: 1, counterparty_name_contains: "ENGIE",
                             confidence: 90)
    end
    let!(:entry) do
      e = build_cash_entry(cash_account, amount_cents: -12_000, label: "Facture")
      e.update!(counterparty_name: "ENGIE")
      e
    end

    it "affiche la suggestion avec son motif sur l'écran à affecter" do
      get finance_unallocated_cash_entries_path

      expect(response.body).to include("Proposition").and include("Énergie")
    end

    it "accepte une suggestion et affecte la ligne" do
      Finance::SuggestAllocations.new.run!
      suggestion = AllocationSuggestion.last

      expect {
        patch finance_allocation_suggestion_path(suggestion, decision: "accept")
      }.to change { CashAllocation.count }.by(1)

      expect(entry.reload.status).to eq("allocated")
    end

    it "refuse une suggestion et le compte sur la règle" do
      Finance::SuggestAllocations.new.run!
      suggestion = AllocationSuggestion.last

      expect {
        patch finance_allocation_suggestion_path(suggestion, decision: "reject")
      }.to change { rule.reload.rejected_count }.by(1)

      expect(suggestion.reload.status).to eq("rejected")
      expect(CashAllocation.count).to eq(0)
    end

    # Il n'existe pas d'acceptation « toutes règles confondues » : c'est le geste
    # par lequel une machine finit par décider à notre place.
    it "exige une règle pour l'acceptation en masse" do
      Finance::SuggestAllocations.new.run!

      expect {
        post bulk_finance_allocation_suggestions_path, params: { confidence: 0 }
      }.not_to change { CashAllocation.count }

      follow_redirect!
      expect(response.body).to include("toutes règles confondues")
    end

    it "refuse de retraiter une suggestion déjà décidée" do
      Finance::SuggestAllocations.new.run!
      suggestion = AllocationSuggestion.last
      patch finance_allocation_suggestion_path(suggestion, decision: "accept")

      expect {
        patch finance_allocation_suggestion_path(suggestion, decision: "reject")
      }.not_to change { rule.reload.rejected_count }

      expect(suggestion.reload.status).to eq("accepted")
    end

    it "accepte en masse au-dessus du seuil, et pas en dessous" do
      Finance::SuggestAllocations.new.run!

      expect {
        post bulk_finance_allocation_suggestions_path,
             params: { allocation_rule_id: rule.id, confidence: 95 }
      }.not_to change { CashAllocation.count }

      expect {
        post bulk_finance_allocation_suggestions_path,
             params: { allocation_rule_id: rule.id, confidence: 80 }
      }.to change { CashAllocation.count }.by(1)
    end
  end

  describe "le contrôle croisé" do
    it "montre les deux mesures et ce qui reste à affecter" do
      build_cash_entry(cash_account, amount_cents: 50_000, label: "Virement client")

      get finance_cross_check_path(month: Date.current.strftime("%Y-%m"))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("encaissé et ventilé").and include("facturé")
      expect(response.body).to include("Reste à affecter")
    end
  end
end
