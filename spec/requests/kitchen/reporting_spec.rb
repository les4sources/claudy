require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Reporting de la cuisine (epic #269, phase 2) : sur une période, ce que la
# cuisine a facturé, encaissé et coûté. La page vit sous Cuisine.
RSpec.describe "Cuisine > Reporting", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "report-req@example.com", first_name: "Groupe", last_name: "Compta") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.new(2026, 10, 10), departure_date: Date.new(2026, 10, 12))
  end

  def line(**attrs)
    order = MealOrder.new({ stay: stay, kind: "repas", people: 10, date: Date.new(2026, 10, 11),
                            responsible_human: steph, cost_cents: 6_000 }.merge(attrs))
    order.skip_notifications = true
    order.tap(&:save!)
  end

  # Le décor comptable : une entité, un exercice, le compte de charge de la
  # cuisine et le compte de recette de la catégorie `meals`.
  def build_accounting(configure: true)
    entity = build_legal_entity
    build_fiscal_year(entity, year: 2026)
    repas = build_general_account(code: "600005", name: "Achats cuisine — repas", klass: 6, nature: "expense")
    banque = build_general_account(code: "550000", name: "Banque")
    recette = build_general_account(code: "700200", name: "Repas", klass: 7, nature: "revenue")
    RevenueMapping.create!(category: "meals", general_account: recette)
    Setting.set(Kitchen::Config::EXPENSE_ACCOUNTS_KEY, repas.id.to_s) if configure
    { entity: entity, expense: repas, bank: banque, revenue: recette }
  end

  describe "la page" do
    it "répond 200 et couvre l'année en cours sans paramètres" do
      get kitchen_reporting_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("value=\"#{Date.current.beginning_of_year.iso8601}\"")
      expect(response.body).to include("value=\"#{Date.current.end_of_year.iso8601}\"")
    end

    it "propose les raccourcis de période attendus" do
      get kitchen_reporting_path

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Année en cours", "Année précédente", "Mois en cours")
    end

    it "affiche le détail des prestations de la période demandée" do
      line

      get kitchen_reporting_path(from: "2026-10-01", to: "2026-10-31")

      expect(response).to have_http_status(:ok)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Groupe Compta", "Repas (midi ou soir)", "Stéphanie")
      expect(body).to include("150") # le prix facturé, en euros
    end

    # La rentabilité de la cuisine se lit sur une période, dans la comptabilité
    # (epic #269) : plus une colonne de coût, plus une marge par prestation.
    it "ne parle plus ni de coût par prestation ni de marge" do
      line
      line(cost_cents: nil)

      get kitchen_reporting_path(from: "2026-10-01", to: "2026-10-31")

      body = CGI.unescapeHTML(response.body)
      expect(body).not_to include("Coût")
      expect(body).not_to include("Marge")
      expect(body).not_to include("sans coût saisi")
    end

    it "affiche un état vide lisible sur une période sans rien" do
      build_accounting
      line(date: Date.new(2026, 11, 15))

      get kitchen_reporting_path(from: "2026-10-01", to: "2026-10-31")

      expect(response).to have_http_status(:ok)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Aucune prestation de cuisine sur cette période.")
      expect(body).to include("Aucune dépense de cuisine sur cette période.")
    end
  end

  describe "l'ancienne adresse" do
    it "redirige vers la page sous Cuisine en conservant la période" do
      get "/reports/kitchen?from=2026-10-01&to=2026-10-31"

      expect(response).to redirect_to("/kitchen/reporting?from=2026-10-01&to=2026-10-31")
    end

    it "redirige aussi sans paramètre" do
      get "/reports/kitchen"

      expect(response).to redirect_to("/kitchen/reporting")
    end
  end

  describe "la navigation" do
    it "mène au reporting depuis la page Cuisine" do
      get kitchen_orders_path

      expect(response.body).to include(kitchen_reporting_path)
    end

    it "pointe l'entrée « Cuisine » du sous-menu Reporting sur la nouvelle adresse" do
      get reports_path

      expect(response.body).to include(kitchen_reporting_path)
      expect(response.body).not_to include("/reports/kitchen")
    end
  end

  describe "les recettes" do
    it "affiche le facturé, l'encaissé, leur écart et ce qui les sépare" do
      decor = build_accounting
      line # 150 € facturés
      post_simple_entry(entity: decor[:entity], debit_account: decor[:bank],
                        credit_account: decor[:revenue], amount_cents: 9_000,
                        entry_date: Date.new(2026, 10, 5), journal: "bank", label: "Acompte")

      get kitchen_reporting_path(from: "2026-01-01", to: "2026-12-31")

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Facturé", "Encaissé", "Écart")
      # `humanized_money_with_symbol` masque les centimes quand ils sont nuls.
      expect(body).to include("150 €") # facturé
      expect(body).to include("90 €")  # encaissé
      expect(body).to include("60 €")  # l'écart
      expect(body).to include("acomptes et des soldes")
    end
  end

  describe "les dépenses" do
    it "totalise les comptes configurés et détaille chaque mouvement" do
      decor = build_accounting
      post_simple_entry(entity: decor[:entity], debit_account: decor[:expense],
                        credit_account: decor[:bank], amount_cents: 4_250,
                        entry_date: Date.new(2026, 3, 12), journal: "purchases",
                        label: "Colruyt — courses buffet")

      get kitchen_reporting_path(from: "2026-01-01", to: "2026-12-31")

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Dépenses", "Détail des dépenses")
      expect(body).to include("42,50 €")
      expect(body).to include("Colruyt — courses buffet")
      expect(body).to include("600005")
      # Le chemin vers l'écriture : le grand livre du compte, à sa date.
      expect(body).to include(finance_ledger_path(general_account_id: decor[:expense].id,
                                                  legal_entity_id: decor[:entity].id,
                                                  from: "2026-03-12", to: "2026-03-12"))
    end

    it "affiche le résultat, encaissé et facturé, net des dépenses" do
      decor = build_accounting
      line # 150 € facturés
      post_simple_entry(entity: decor[:entity], debit_account: decor[:expense],
                        credit_account: decor[:bank], amount_cents: 5_000,
                        entry_date: Date.new(2026, 3, 12), journal: "purchases", label: "Courses")
      post_simple_entry(entity: decor[:entity], debit_account: decor[:bank],
                        credit_account: decor[:revenue], amount_cents: 12_000,
                        entry_date: Date.new(2026, 10, 5), journal: "bank", label: "Encaissement")

      get kitchen_reporting_path(from: "2026-01-01", to: "2026-12-31")

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Résultat")
      expect(body).to include("70 €")  # encaissé 120 − dépenses 50
      expect(body).to include("100 €") # facturé 150 − dépenses 50
    end

    # Un total de 0 € ressemblerait à une cuisine qui n'a rien coûté.
    it "dit qu'aucun compte n'est configuré et renvoie vers les paramètres" do
      build_accounting(configure: false)

      get kitchen_reporting_path(from: "2026-01-01", to: "2026-12-31")

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Aucun compte de charge n'est configuré pour la cuisine.")
      expect(body).to include(kitchen_settings_path)
    end
  end

  describe "l'export des prestations" do
    it "livre un CSV lisible par Excel" do
      line

      get kitchen_reporting_path(from: "2026-10-01", to: "2026-10-31", format: :csv)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("cuisine-2026-10-01-2026-10-31.csv")
      expect(response.body).to start_with("﻿") # BOM : sans lui, Excel casse les accents
      expect(response.body).to include("Date;Moment;Client")
      expect(response.body).to include("Groupe Compta", "150,00")
      # Ni coût ni marge : la colonne qui suit le prix est celle de la personne.
      expect(response.body).not_to include("Coût")
      expect(response.body).not_to include("Marge")
      expect(response.body).to include("150,00;Stéphanie")
    end
  end

  describe "reporting mensuel" do
    it "porte une colonne Cuisine dont le total mensuel tient compte" do
      line

      get reports_path(year: 2026)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cuisine")
      # 150 € de cuisine en octobre, repris dans le total du mois.
      expect(response.body).to include("150,00 €")
      expect(Reports::KitchenRevenue.revenue_by_month(2026)[10]).to eq(15_000)
    end

    it "affiche zéro, pas une erreur, sur une année sans cuisine" do
      get reports_path(year: 2019)

      expect(response).to have_http_status(:ok)
    end
  end
end
