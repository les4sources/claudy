require "rails_helper"

# Filtres de l'index Séjours (Michael 2026-10-15) : statut du dossier et
# « Solde à payer ».
RSpec.describe "Index Séjours — filtres statut et solde", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-filtres@les4sources.be", password: "password123") }
  let(:trimestre) { Date.today.beginning_of_quarter }
  before { sign_in user }

  def create_stay(last:, status:, total_cents:, arrival: trimestre + 3)
    customer = Customer.create!(email: "#{last.downcase}@example.com", first_name: "Client", last_name: last)
    Stay.create!(customer: customer, source: "manual", status: status,
                 arrival_date: arrival, departure_date: arrival + 2,
                 total_amount_cents: total_cents)
  end

  let!(:attente)  { create_stay(last: "Attente",  status: "pending",       total_cents: 10_000) }
  let!(:preconf)  { create_stay(last: "Preconf",  status: "pre_confirmed", total_cents: 10_000) }
  let!(:solde)    { create_stay(last: "Solde",    status: "confirmed",     total_cents: 30_000) }
  let!(:paye)     { create_stay(last: "Paye",     status: "confirmed",     total_cents: 20_000) }
  let!(:annule)   { create_stay(last: "Annule",   status: "canceled",      total_cents: 15_000) }
  let!(:historic) { create_stay(last: "Historic", status: "cancelled",     total_cents: 0) }

  before do
    Payment.create!(stay: solde, amount_cents: 10_000, status: "paid", payment_method: "transfer")
    Payment.create!(stay: paye,  amount_cents: 20_000, status: "paid", payment_method: "transfer")
  end

  def noms_affiches
    %w[Attente Preconf Solde Paye Annule Historic].select { |nom| response.body.include?("Client #{nom}") }
  end

  # Défaut (Michael 2026-10-18) : sans statut dans l'URL, les confirmés.
  it "montre les séjours confirmés par défaut et propose les pastilles" do
    get stays_path
    expect(response).to have_http_status(:ok)
    expect(noms_affiches).to eq(%w[Solde Paye])
    expect(response.body).to include("Solde à payer")
    expect(response.body).to include("Pré-confirmé")
    expect(response.body).to match(%r{<a [^>]*aria-current="true"[^>]*>Confirmé</a>})
  end

  it "« Tous » montre tous les statuts et le reste dans la navigation" do
    get stays_path(status: "all")
    expect(noms_affiches).to eq(%w[Attente Preconf Solde Paye Annule Historic])
    expect(response.body).to match(%r{<a [^>]*aria-current="true"[^>]*>Tous</a>})
    expect(response.body).to include("status=all&amp;year=#{trimestre.year}")
  end

  it "filtre par statut" do
    get stays_path(status: "confirmed")
    expect(noms_affiches).to eq(%w[Solde Paye])
  end

  it "« Annulé » couvre les deux orthographes" do
    get stays_path(status: "canceled")
    expect(noms_affiches).to eq(%w[Annule Historic])
  end

  it "retombe sur le défaut pour un statut inconnu" do
    get stays_path(status: "nimporte")
    expect(noms_affiches).to eq(%w[Solde Paye])
  end

  it "ne garde que les séjours non annulés avec un solde exigible" do
    get stays_path(status: "all", solde: "1")
    expect(noms_affiches).to eq(%w[Attente Preconf Solde])
    total = ApplicationController.helpers.humanized_money_with_symbol(Money.new(40_000))
    expect(response.body).to include(total)
  end

  it "combine statut et solde" do
    get stays_path(status: "confirmed", solde: "1")
    expect(noms_affiches).to eq(%w[Solde])
  end

  it "combine les filtres avec la recherche" do
    get stays_path(q: "Client", status: "pending")
    expect(noms_affiches).to eq(%w[Attente])
  end

  it "reporte les filtres dans la navigation par trimestre" do
    get stays_path(status: "confirmed", solde: "1")
    expect(response.body).to include("solde=1&amp;status=confirmed&amp;year=#{trimestre.year}")
  end

  # Un trimestre qui n'a de séjours que hors filtre s'éteint.
  it "compte les trimestres selon les filtres" do
    autre = trimestre.month == 1 ? 2 : 1
    create_stay(last: "Autre", status: "confirmed", total_cents: 5_000,
                arrival: Date.new(trimestre.year, (autre - 1) * 3 + 1, 10))

    get stays_path(status: "confirmed")
    expect(response.body).to include("quarter=#{autre}&amp;status=confirmed")

    get stays_path(status: "pending")
    expect(response.body).not_to include("quarter=#{autre}&amp;status=pending")

    get stays_path(status: "all", solde: "1")
    expect(response.body).to include("quarter=#{autre}&amp;solde=1&amp;status=all")
  end

  it "dit quand aucun séjour ne correspond aux filtres" do
    get stays_path(status: "pre_confirmed", solde: "1", year: trimestre.year - 5, quarter: 1)
    expect(response.body).to include("Aucun séjour ne correspond à ces filtres.")
  end
end
