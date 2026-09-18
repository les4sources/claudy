require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #245, phase 3 — l'onglet comptable, le règlement et « À payer ».
RSpec.describe "Événements — page comptable et règlement (epic #245, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "admin-settlement@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank_general) { build_general_account(code: "550000", name: "Banque") }
  let!(:fee_account) { build_general_account(code: "616000", name: "Rémunérations d'intervenants", klass: 6, nature: "expense") }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:cash_account) { build_cash_account(entity, bank_general) }
  let!(:category) { EventCategory.create!(name: "Formation") }
  let!(:team) { Team.create!(name: "Transmission") }
  let!(:seb) { Human.create!(name: "Sébastien") }
  let!(:magali) { Human.create!(name: "Magali") }

  let(:event) do
    Event.create!(name: "Stage low-tech", event_category: category, team: team,
                  starts_at: Date.new(2026, 6, 10), ends_at: Date.new(2026, 6, 12),
                  starts_at_date: Date.new(2026, 6, 10), ends_at_date: Date.new(2026, 6, 12),
                  organizer_share_percent: 70)
  end

  before { sign_in user }

  def prepare!(revenue: 100_000, costs: 30_000)
    entry = build_cash_entry(cash_account, amount_cents: revenue)
    entry.cash_allocations.create!(general_account: bank_general, amount_cents: revenue,
                                   legal_entity: entity, document: event)
    EventCost.create!(event: event, label: "Location de salle", amount_cents: costs, kind: "other")
    EventOrganizer.create!(event: event, human: seb, weight: 2)
    EventOrganizer.create!(event: event, human: magali, weight: 1)
    event.reload
  end

  describe "l'onglet Comptabilité" do
    it "montre le récapitulatif et une ligne par organisateur" do
      prepare!
      get event_path(event, tab: "comptabilite")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Répartition")
      expect(response.body).to include("Base de partage")
      expect(response.body).to include("Part des organisateurs")
      expect(response.body).to include("Part des 4 Sources")
      expect(response.body).to include("Sébastien", "Magali")
      expect(CGI.unescapeHTML(response.body)).to include("Régler l'événement")
      expect(response.body).to include("recalculé à chaque affichage")
    end

    it "explique une base négative au lieu de la partager" do
      prepare!(revenue: 10_000, costs: 30_000)
      get event_path(event, tab: "comptabilite")

      expect(response.body).to include("nulle ou négative")
      expect(CGI.unescapeHTML(response.body)).not_to include("Régler l'événement")
    end

    it "invite à ajouter des organisateurs quand il n'y en a pas" do
      prepare!
      event.event_organizers.destroy_all

      get event_path(event, tab: "comptabilite")
      expect(response.body).to include("Ajoutez des organisateurs")
      expect(CGI.unescapeHTML(response.body)).not_to include("Régler l'événement")
    end
  end

  describe "« Régler l'événement »" do
    it "fige le partage et le dit" do
      prepare!

      expect { post event_settlement_path(event) }.to change { EventSettlement.count }.by(1)

      follow_redirect!
      expect(response.body).to include("Réglé — en attente de virement")
      expect(response.body).not_to include("recalculé à chaque affichage")
      expect(response.body).to include("contre-passation")
    end

    it "refuse en clair un deuxième règlement" do
      prepare!
      post event_settlement_path(event)
      post event_settlement_path(event)

      follow_redirect!
      expect(response.body).to include("déjà réglé")
      expect(EventSettlement.count).to eq(1)
    end
  end

  describe "« À payer »" do
    it "liste une part par organisateur, avec le nom de l'événement en communication" do
      prepare!
      post event_settlement_path(event)

      get finance_payables_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sébastien", "Magali")
      expect(response.body).to include("Stage low-tech")
    end

    it "retire une part virée de la file" do
      prepare!
      post event_settlement_path(event)
      line = EventSettlement.last.event_settlement_lines.find_by(human: seb)

      entry = build_cash_entry(cash_account, amount_cents: -line.amount_cents, label: "Virement Sébastien")
      entry.cash_allocations.create!(general_account: supplier_account, amount_cents: -line.amount_cents,
                                     legal_entity: entity, document: line)

      get finance_payables_path
      expect(response.body).to include("Magali")
      expect(response.body).not_to include(line.payable_reference)
    end
  end

  describe "rake accounting:verify_event_settlements" do
    it "ne signale rien sur un règlement sain" do
      prepare!
      post event_settlement_path(event)

      settlement = EventSettlement.last
      expect(settlement.posted_at).to be_present
      expect(JournalEntry.unscoped.find_by(source: settlement, journal: "purchases")).to be_present
      expect(settlement.event_settlement_lines.sum(:amount_cents)).to eq(settlement.organizers_cents)
      expect(settlement.organizers_cents + settlement.house_cents).to eq(settlement.base_cents)
    end
  end
end
