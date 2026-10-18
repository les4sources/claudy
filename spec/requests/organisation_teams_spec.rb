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

    it "montre sur chaque carte le résultat de l'année et le budget" do
      TeamBudget.create!(team: team, year: Date.current.year, expense_cents: 100_000)
      Team.create!(name: "Pôle Technique", kind: "support")

      get organisation_teams_path

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Résultat #{Date.current.year}", "0 % des charges prévues",
                              "Pas de budget #{Date.current.year}")
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

    it "ouvre sur les comptes : santé, budget, dépenses à valider" do
      get team_path(team)

      body = CGI.unescapeHTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(body).to include("Comptes #{Date.current.year}", "Santé financière",
                              "Budget #{Date.current.year}", "Dépenses à valider")
      expect(body.index("Santé financière")).to be < body.index("Membres")
      expect(body).to include("Rien n'attend le oui du pôle.")
      expect(body).to include(edit_team_budget_path(team, Date.current.year))
    end

    context "le bloc Comptes" do
      let(:entity) { build_legal_entity }
      let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
      let(:bank) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
      let(:sales) { build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue") }

      it "affiche produits, charges et résultat de l'année" do
        Accounting::PostDocument.new(
          legal_entity: entity, journal: "sales", entry_date: Date.current.beginning_of_year + 2.months,
          label: "Vente cuisine",
          lines: [{ account: bank, debit_cents: 50_000 },
                  { account: sales, credit_cents: 50_000, team: team }]
        ).run!

        get team_path(team)

        body = CGI.unescapeHTML(response.body)
        expect(body).to include("Résultat #{Date.current.year}")
        expect(body).to include("+#{ActiveSupport::NumberHelper.number_to_currency(500, unit: "€", precision: 0)}")
        expect(body).to include("À l'équilibre")
      end

      it "rappelle les lignes de trésorerie non affectées" do
        cash_account = build_cash_account(entity, bank)
        build_cash_entry(cash_account, entry_date: Date.current.beginning_of_year + 1.month)

        get team_path(team)

        body = CGI.unescapeHTML(response.body)
        expect(body).to include("Chiffres incomplets", "attend encore d'être affectée")
      end

      it "compare le réel au budget de l'année" do
        TeamBudget.create!(team: team, year: Date.current.year, revenue_cents: 1_000_000, expense_cents: 400_000,
                           notes: "Décidé au rassemblement de janvier")

        get team_path(team)

        body = CGI.unescapeHTML(response.body)
        expect(body).to include("Résultat prévu sur l'année", "Décidé au rassemblement de janvier")
        expect(body).not_to include("Pas encore de budget")
      end

      it "suit l'année demandée" do
        get team_path(team, year: 2024)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Comptes 2024", "Pas encore de budget pour 2024")
      end

      it "retombe sur l'année en cours quand l'année demandée n'a pas de sens" do
        get team_path(team, year: "n'importe quoi")

        expect(response.body).to include("Comptes #{Date.current.year}")
      end
    end
  end
end
