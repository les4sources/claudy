require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #245, phase 2 — les recettes rattachées à l'événement.
RSpec.describe "Recettes rattachées à un événement", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "evt@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:banque_compte) { build_general_account(code: "550000", name: "Banque") }
  let(:recettes) { build_general_account(code: "701000", name: "Formations", klass: 7, nature: "revenue") }
  let(:banque) { build_cash_account(entity, banque_compte) }
  let(:categorie) { EventCategory.create!(name: "Stage") }
  let!(:event) do
    Event.create!(name: "Stage lowtech", event_category: categorie,
                  starts_at: Time.zone.parse("2026-06-10 09:00"),
                  ends_at: Time.zone.parse("2026-06-12 17:00"),
                  sales_amount_cents: 100_000)
  end

  before { sign_in user }

  def entry(amount_cents: 45_000, communication: "STAGE LOWTECH")
    e = build_cash_entry(banque, amount_cents: amount_cents, label: "Virement Dupont")
    e.update!(communication: communication)
    e
  end

  describe "le formulaire d'affectation" do
    it "propose l'événement, sur « À affecter » comme sur la fiche d'une ligne" do
      ligne = entry

      get finance_unallocated_cash_entries_path
      expect(response.body).to include("Stage lowtech")
      expect(response.body).to include("cash_allocation[event_id]")

      get finance_cash_entry_path(ligne)
      expect(response.body).to include("Stage lowtech")
      expect(response.body).to include("cash_allocation[event_id]")
    end

    it "rattache l'événement à l'allocation, ligne entrante" do
      ligne = entry

      post finance_cash_entry_allocations_path(ligne),
           params: { cash_allocation: { general_account_id: recettes.id, legal_entity_id: entity.id,
                                        amount: "450,00", event_id: event.id } }

      allocation = ligne.cash_allocations.sole
      expect(allocation.document).to eq(event)
      expect(event.reload.recorded_revenue_cents).to eq(45_000)
    end

    it "rattache aussi une ligne SORTANTE — un remboursement est une recette négative" do
      ligne = entry(amount_cents: -12_000)

      post finance_cash_entry_allocations_path(ligne),
           params: { cash_allocation: { general_account_id: recettes.id, legal_entity_id: entity.id,
                                        amount: "-120,00", event_id: event.id } }

      expect(ligne.cash_allocations.sole.document).to eq(event)
      expect(event.reload.recorded_revenue_cents).to eq(-12_000)
    end

    it "n'oblige à rien : sans événement choisi, l'allocation reste sans document" do
      ligne = entry

      post finance_cash_entry_allocations_path(ligne),
           params: { cash_allocation: { general_account_id: recettes.id, legal_entity_id: entity.id,
                                        amount: "450,00", event_id: "" } }

      expect(ligne.cash_allocations.sole.document).to be_nil
    end
  end

  describe "les règles de rapprochement" do
    let!(:rule) do
      AllocationRule.create!(label: "Stage lowtech", communication_contains: "STAGE LOWTECH",
                             general_account: recettes, legal_entity: entity, event: event,
                             confidence: 90, position: 1)
    end

    it "propose l'événement dans la suggestion, sans créer d'allocation" do
      ligne = entry

      expect { Finance::SuggestAllocations.new(cash_entries: [ligne]).run! }
        .not_to change(CashAllocation, :count)

      suggestion = ligne.allocation_suggestions.sole
      expect(suggestion.event).to eq(event)
      expect(suggestion.rationale).to include("Stage lowtech")
    end

    it "pose le document sur l'allocation quand un humain accepte la suggestion" do
      ligne = entry
      Finance::SuggestAllocations.new(cash_entries: [ligne]).run!
      suggestion = ligne.allocation_suggestions.sole

      Finance::AcceptSuggestion.new(suggestion: suggestion).run!

      expect(ligne.reload.cash_allocations.sole.document).to eq(event)
    end

    it "s'édite depuis le formulaire de règle" do
      get edit_finance_allocation_rule_path(rule)

      expect(response.body).to include("Événement", "Stage lowtech")
    end
  end

  describe "l'onglet Comptabilité de l'événement" do
    it "le dit quand aucune recette n'est rattachée" do
      get event_path(event, tab: "comptabilite")

      expect(response.body).to include("Aucune recette rattachée")
    end

    it "liste les allocations avec leur total, et barre l'estimation" do
      ligne = entry
      ligne.cash_allocations.create!(general_account: recettes, legal_entity: entity,
                                     amount_cents: 45_000, document: event, label: "Inscriptions")

      get event_path(event, tab: "comptabilite")

      expect(response.body).to include("Inscriptions", "701000")
      expect(response.body).to include("Total encaissé")
      expect(response.body).to include("450,00")
      expect(response.body).to include("line-through")
    end

    it "ne barre pas l'estimation tant qu'aucune recette n'est rattachée" do
      get event_path(event, tab: "comptabilite")

      expect(response.body).not_to include("line-through")
    end

    it "signale les séjours liés par une réservation d'espace, sans rien rattacher" do
      customer = Customer.create!(email: "groupe@example.com", first_name: "Groupe",
                                  customer_type: "individual")
      stay = Stay.create!(customer: customer, status: "confirmed",
                          arrival_date: Date.new(2026, 6, 10), departure_date: Date.new(2026, 6, 12))
      booking = SpaceBooking.create!(firstname: "Groupe", email: "groupe@example.com",
                                     from_date: Date.new(2026, 6, 10), to_date: Date.new(2026, 6, 12),
                                     event: event)
      StayItem.create!(stay: stay, bookable: booking)

      get event_path(event, tab: "comptabilite")

      # `=` échappe l'apostrophe (&#39;) : on assert sur la partie sans apostrophe.
      expect(response.body).to include("1 séjour lié par une réservation")
      expect(response.body).to include("rien n'est rattaché d'office")
      expect(event.reload.recorded_revenue_cents).to eq(0)
    end
  end
end
