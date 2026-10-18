require "rails_helper"

# Apporteur visible pour l'équipe (Michael, 2026-10-18) : pastille « Via
# Semisto » sur la fiche et dans l'index, filtre de l'index.
RSpec.describe "Séjours — apporteur", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-apporteur@les4sources.be", password: "password123") }
  let(:trimestre) { Date.today.beginning_of_quarter }
  before { sign_in user }

  def create_stay(last:, referral: nil)
    customer = Customer.create!(email: "#{last.downcase}@example.com", first_name: "Client", last_name: last)
    Stay.create!(customer: customer, source: "reservation", status: "pending", referral: referral,
                 arrival_date: trimestre + 3, departure_date: trimestre + 5)
  end

  let!(:apporte) { create_stay(last: "Apporte", referral: "semisto") }
  let!(:direct)  { create_stay(last: "Direct") }

  it "affiche la pastille dans l'index et propose le filtre" do
    get stays_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Client Apporte", "Client Direct")
    expect(response.body.scan("Séjour apporté par Semisto").size).to eq(1)
    expect(response.body).to include("apporteur=semisto")
  end

  it "filtre les séjours apportés par Semisto" do
    get stays_path(apporteur: "semisto")
    expect(response.body).to include("Client Apporte")
    expect(response.body).not_to include("Client Direct")
  end

  it "ignore un apporteur inconnu dans le filtre" do
    get stays_path(apporteur: "inconnu")
    expect(response.body).to include("Client Apporte", "Client Direct")
  end

  it "montre l'apporteur sur la fiche du séjour" do
    get stay_path(apporte)
    expect(response.body).to include("Via Semisto")

    get stay_path(direct)
    expect(response.body).not_to include("Via Semisto")
  end
end
