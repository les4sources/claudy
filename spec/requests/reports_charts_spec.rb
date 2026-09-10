require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #276 — les deux graphes de `/reports`. On vérifie qu'ils s'affichent,
# qu'ils suivent l'année de la navigation, et surtout que le graphe des
# hébergements retombe sur le total du tableau juste au-dessus.
RSpec.describe "Reporting — graphes de l'année", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "graphes@les4sources.be", password: "password123") }
  let!(:lodging) { Lodging.create!(name: "La Chevêche test", show_on_reports: true) }

  before { sign_in user }

  def booking(year:, month:, price_cents:)
    Booking.create!(lodging: lodging, status: "confirmed", price_cents: price_cents,
                    from_date: Date.new(year, month, 10), to_date: Date.new(year, month, 12),
                    firstname: "Ana", lastname: "Test", email: "ana@example.com",
                    adults: 2, children: 0)
  end

  it "affiche les deux graphes sur une année qui porte des réservations" do
    booking(year: 2026, month: 4, price_cents: 120_000)

    get reports_path(year: 2026)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hébergements — répartition sur l&#39;année")
    expect(response.body).to include("Chiffre d&#39;affaires Accueil — répartition")
    expect(response.body).to include("La Chevêche test")
  end

  it "affiche un état vide lisible sur une année sans aucune donnée" do
    get reports_path(year: 2019)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucun revenu d'hébergement enregistré")
    expect(response.body).to include("Aucun chiffre d'affaires enregistré")
  end

  it "suit l'année de la navigation" do
    booking(year: 2025, month: 2, price_cents: 50_000)

    get reports_path(year: 2025)
    expect(response.body).to include("Total 2025")

    get reports_path(year: 2024)
    expect(response.body).to include("Aucun chiffre d'affaires enregistré")
  end

  it "dit que le bar n'est pas encore encodé plutôt que d'afficher zéro" do
    booking(year: 2026, month: 4, price_cents: 120_000)
    build_general_account(code: "701001", name: "Bar", klass: 7, nature: "revenue")
    build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue")

    get reports_path(year: 2026)

    expect(response.body).to include("pas encore encodé en comptabilité")
  end

  it "fait retomber le graphe sur le total « Hébergements » du tableau" do
    booking(year: 2026, month: 4, price_cents: 120_000)
    booking(year: 2026, month: 9, price_cents: 80_000)

    breakdown = Reports::AnnualBreakdown.new(year: 2026)
    table_total = Booking.where(status: "confirmed",
                                from_date: Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).sum(:price_cents)

    expect(breakdown.lodging_total_cents).to eq(table_total)

    get reports_path(year: 2026)
    expect(response.body).to include(ActiveSupport::NumberHelper.number_to_currency(2_000.0, unit: "€"))
  end
end
