require "rails_helper"

# Apporteur visible pour l'équipe (Michael, 2026-10-18) : pastille « Via
# Semisto » sur la fiche et dans l'index, filtre de l'index.
RSpec.describe "Séjours — apporteur", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-apporteur@les4sources.be", password: "password123") }
  let(:trimestre) { Date.today.beginning_of_quarter }
  before { sign_in user }

  # Hébergement 400 € dans un séjour de 500 € : la commission de 10 % vaut 40 €.
  def create_stay(last:, referral: nil, status: "pending", lodging_cents: 40_000, total_cents: 50_000, paid_cents: 0)
    customer = Customer.create!(email: "#{last.downcase}@example.com", first_name: "Client", last_name: last)
    stay = Stay.create!(customer: customer, source: "reservation", status: status, referral: referral,
                        arrival_date: trimestre + 3, departure_date: trimestre + 5)
    booking = Booking.create!(firstname: "Client", from_date: stay.arrival_date, to_date: stay.departure_date,
                              adults: 2, status: status, price_cents: lodging_cents)
    stay.stay_items.create!(bookable: booking)
    stay.update_columns(total_amount_cents: total_cents)
    Payment.create!(stay: stay, amount_cents: paid_cents, status: "paid", payment_method: "transfer") if paid_cents.positive?
    stay
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

  describe "commission" do
    let!(:due_1) { create_stay(last: "DueUn",   referral: "semisto", status: "confirmed", paid_cents: 50_000) }
    let!(:due_2) { create_stay(last: "DueDeux", referral: "semisto", status: "confirmed", lodging_cents: 25_000, total_cents: 30_000, paid_cents: 30_000) }
    let!(:partiel) { create_stay(last: "Partiel", referral: "semisto", status: "confirmed", paid_cents: 10_000) }
    let!(:direct_paye) { create_stay(last: "DirectPaye", status: "confirmed", paid_cents: 50_000) }

    it "totalise sur l'index filtré ce qui est dû, et compte le reste" do
      get stays_path(apporteur: "semisto")
      resume = response.body[/data-testid="referral-summary".*?<\/div>/m]
      expect(resume).to be_present
      # 10 % de 400 € + 10 % de 250 € = 65 € ; « Partiel » et « Apporte » ne comptent pas.
      expect(resume).to include("Commission Semisto due", "10 %", "65 €", "sur 2 séjours")
      expect(resume).to include("2 autres séjours")
    end

    it "n'affiche pas de total sans le filtre" do
      get stays_path
      expect(response.body).not_to include("referral-summary")
    end

    it "montre la commission due sur la fiche d'un séjour confirmé et payé" do
      get stay_path(due_1)
      expect(response.body).to include("Commission 10 % : 40 € — due")
    end

    it "dit pourquoi elle n'est pas encore due" do
      get stay_path(partiel)
      expect(response.body).to include("pas encore due (séjour pas entièrement payé)")

      get stay_path(apporte)
      expect(response.body).to include("séjour pas encore confirmé, séjour pas entièrement payé")
    end

    it "n'affiche rien sur un séjour sans apporteur" do
      get stay_path(direct_paye)
      expect(response.body).not_to include("Commission 10 %")
    end
  end
end
