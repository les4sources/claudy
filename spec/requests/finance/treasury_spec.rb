require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La trésorerie à l'écran (2026-09-29) : le résumé sur la page Comptabilité, le
# détail sur sa propre page, et les vieux restes dus rangés à part.
RSpec.describe "Comptabilité > Trésorerie", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-tresorerie@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Triodos"), name: "Triodos") }
  let(:customer) { Customer.create!(first_name: "Jeanne", last_name: "Dupont", email: "jeanne@example.test") }

  before do
    sign_in user
    import = CodaImport.create!(filename: "r.cod", sha256: SecureRandom.hex(32), content: "x")
    CodaStatement.create!(coda_import: import, cash_account: bank, sequence_number: "001", period_year: 2026,
                          old_balance_cents: 0, new_balance_cents: 816_141, new_balance_date: Date.current - 3)
  end

  def stay(arrival:, departure:, total:)
    Stay.create!(customer: customer, arrival_date: arrival, departure_date: departure,
                 total_amount_cents: total, payment_status: "pending", status: "confirmed")
  end

  it "résume la trésorerie en tête de la page Comptabilité" do
    get finance_accounting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Trésorerie de la Fondation")
    expect(response.body).to include("8 161,41 €").or include("8.161,41 €").or include("8161,41 €")
    expect(response.body).to include(finance_treasury_path)
    expect(response.body).to include("<svg")
  end

  it "détaille ce qui doit rentrer, et range à part les restes dus de plus d'un an" do
    a_venir = stay(arrival: Date.current + 10, departure: Date.current + 12, total: 60_000)
    en_retard = stay(arrival: Date.current - 60, departure: Date.current - 58, total: 20_000)
    vieux = stay(arrival: Date.current - 800, departure: Date.current - 798, total: 15_000)

    get finance_treasury_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    ids = ->(list) { html.css("[data-treasury-list='#{list}'] tr[data-stay-id]").map { |tr| tr["data-stay-id"].to_i } }
    expect(ids.call("upcoming")).to eq([a_venir.id])
    expect(ids.call("late")).to eq([en_retard.id])
    expect(ids.call("stale")).to eq([vieux.id])
    expect(html.at_css("[data-treasury-stale] summary").text).to include("1 séjour(s)")
  end

  it "signale un relevé bancaire de plus d'une semaine" do
    CodaStatement.update_all(new_balance_date: Date.current - 19)

    get finance_treasury_path

    expect(response.body).to include("il y a 19 jours")
    expect(response.body).to include(finance_coda_imports_path)
  end

  it "dit son vide sans fondation" do
    entity.update!(form: "srl")

    get finance_treasury_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucune fondation")
  end
end
