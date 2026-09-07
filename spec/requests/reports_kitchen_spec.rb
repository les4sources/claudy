require "rails_helper"

# Reporting > Cuisine (epic #219, phase 5).
RSpec.describe "Reporting > Cuisine", type: :request do
  include Devise::Test::IntegrationHelpers

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

  it "affiche le détail, les totaux et la marge sur la plage demandée" do
    line

    get kitchen_reports_path(from: "2026-10-01", to: "2026-10-31")

    expect(response).to have_http_status(:ok)
    body = CGI.unescapeHTML(response.body)
    expect(body).to include("Groupe Compta", "Repas (midi ou soir)", "Stéphanie")
    expect(body).to include("150", "60", "90") # prix, coût, marge en euros
  end

  it "borne la plage et se rabat sur le mois en cours sans paramètres" do
    line(date: Date.new(2026, 11, 15))

    get kitchen_reports_path(from: "2026-10-01", to: "2026-10-31")
    expect(response.body).to include("Aucune prestation")

    get kitchen_reports_path
    expect(response).to have_http_status(:ok)
  end

  it "signale les lignes dont le coût manque" do
    line(cost_cents: nil)

    get kitchen_reports_path(from: "2026-10-01", to: "2026-10-31")

    expect(CGI.unescapeHTML(response.body)).to include("sans coût saisi")
  end

  it "exporte le détail en CSV lisible par Excel" do
    line

    get kitchen_reports_path(from: "2026-10-01", to: "2026-10-31", format: :csv)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("cuisine-2026-10-01-2026-10-31.csv")
    expect(response.body).to start_with("﻿") # BOM : sans lui, Excel casse les accents
    expect(response.body).to include("Date;Moment;Client")
    expect(response.body).to include("Groupe Compta", "150,00", "60,00", "90,00")
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
