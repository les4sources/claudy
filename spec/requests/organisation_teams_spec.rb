require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #239, phase 3 — la page du pôle et son annuaire, côté Organisation.
RSpec.describe "Organisation — pôles", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "pole@les4sources.be", password: "password123") }
  let!(:parent) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let!(:team) { Team.create!(name: "Pôle Cuisine", kind: "analytic", parent: parent, analytic_code: "CUI") }
  let!(:human) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let!(:membership) { TeamMembership.create!(team: team, human: human, role: "referent") }

  before { sign_in user }

  describe "l'annuaire" do
    it "liste les pôles en cartes qui mènent à leur page" do
      get organisation_teams_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pôle Cuisine")
      expect(response.body).to include("Pôle Accueil")
      expect(response.body).to include(team_path(team))
      expect(response.body).to include("Stéphanie")
    end
  end

  describe "la page du pôle" do
    it "affiche l'en-tête, le parent et les référent·e·s" do
      get team_path(team)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pôle Cuisine")
      expect(response.body).to include("Pôle analytique")
      expect(response.body).to include("Rattaché à")
      expect(response.body).to include("Stéphanie")
      expect(response.body).to include("Référent·e")
    end

    it "se range sous Organisation, pas sous Paramètres" do
      get team_path(team)

      expect(response.body).to include("subnav-organisation")
      expect(response.body).not_to include("subnav-settings")
    end

    it "montre les rassemblements du pôle, à venir et passés" do
      category = GatheringCategory.create!(name: "Collectif", color: "emerald")
      soon = Gathering.create!(name: "Réunion cuisine", gathering_category: category,
                               starts_at: 3.days.from_now, ends_at: 3.days.from_now + 2.hours)
      done = Gathering.create!(name: "Bilan de saison", gathering_category: category,
                               starts_at: 10.days.ago, ends_at: 10.days.ago + 2.hours)
      [soon, done].each { |g| g.teams << team }

      get team_path(team)

      expect(response.body).to include("Réunion cuisine")
      expect(response.body).to include("Bilan de saison")
    end

    it "montre les décisions prises lors de ces rassemblements" do
      category = GatheringCategory.create!(name: "Collectif", color: "emerald")
      gathering = Gathering.create!(name: "Réunion cuisine", gathering_category: category,
                                    starts_at: 10.days.ago, ends_at: 10.days.ago + 2.hours)
      gathering.teams << team
      Decision.create!(title: "On passe au bio", summary: "Adopté à l'unanimité.",
                       taken_at: 10.days.ago, recorded_by: human, gathering: gathering)

      get team_path(team)

      expect(response.body).to include("On passe au bio")
    end

    it "réserve l'emplacement « À valider » sans rien y afficher" do
      get team_path(team)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("À valider")
    end

    context "le bloc Finances" do
      let(:entity) { build_legal_entity }
      let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
      let(:bank) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
      let(:sales) { build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue") }

      it "affiche produits, charges et net sur la période" do
        Accounting::PostDocument.new(
          legal_entity: entity, journal: "sales", entry_date: Date.current.beginning_of_year + 2.months,
          label: "Vente cuisine",
          lines: [{ account: bank, debit_cents: 50_000 },
                  { account: sales, credit_cents: 50_000, team: team }]
        ).run!

        get team_path(team)

        expect(response.body).to include("Finances du pôle")
        expect(response.body).to include(ActiveSupport::NumberHelper.number_to_currency(500.0, unit: "€"))
      end

      it "rappelle les lignes de trésorerie non affectées" do
        cash_account = build_cash_account(entity, bank)
        build_cash_entry(cash_account, entry_date: Date.current.beginning_of_year + 1.month)

        get team_path(team)

        expect(response.body).to include("ne sont dans aucun pôle").or include("attend encore d'être affectée")
      end

      it "suit la période demandée" do
        get team_path(team, from: "2024-01-01", to: "2024-12-31")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("2024-01-01")
      end
    end
  end
end
