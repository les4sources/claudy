require "rails_helper"

RSpec.describe "Vue admin — Stays récents (/stays/recents)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:customer) { Customer.create!(email: "recent@example.com", customer_type: "individual") }

  describe "garde Devise (AC-T2-24, préserve ISC-3)" do
    it "redirige un visiteur non authentifié vers sign_in" do
      get recent_stays_path
      expect(response).to redirect_to("/users/sign_in")
    end
  end

  describe "filtre par source (AC-T2-23)" do
    let(:user) { User.create!(email: "agent-recent@les4sources.be", password: "password123") }
    before { sign_in user }

    # Deux clients distincts pour distinguer les deux canaux dans le rendu : la
    # vue affiche le canal + le contact, pas l'id brut du Stay.
    let(:tally_customer) { Customer.create!(email: "tally@example.com", first_name: "Tilda", last_name: "Legacy") }
    let!(:reservation_booking) do
      b = Booking.new(firstname: "Rémi", lastname: "Direct", from_date: Date.today + 3, to_date: Date.today + 5, adults: 1, status: "pending")
      b.generate_token; b.save!; b
    end
    let!(:reservation_stay) do
      s = Stay.create!(customer: customer, source: "reservation", status: "pending",
                       arrival_date: Date.today + 3, departure_date: Date.today + 5)
      s.stay_items.create!(bookable: reservation_booking); s
    end
    let!(:tally_booking) do
      b = Booking.new(firstname: "Tilda", lastname: "Legacy", from_date: Date.today + 10, to_date: Date.today + 12, adults: 1, status: "confirmed")
      b.generate_token; b.save!; b
    end
    let!(:tally_stay) do
      s = Stay.create!(customer: tally_customer, source: "tally_legacy", status: "confirmed",
                       arrival_date: Date.today + 10, departure_date: Date.today + 12)
      s.stay_items.create!(bookable: tally_booking); s
    end

    it "liste tous les séjours sans filtre" do
      get recent_stays_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rémi Direct")     # canal reservation
      expect(response.body).to include("Tilda Legacy")    # canal tally_legacy
    end

    it "lie le nom du client vers sa fiche (accès au détail du séjour)" do
      get recent_stays_path
      expect(response.body).to include(%(href="#{customer_path(customer)}"))
    end

    it "restreint la liste au canal demandé" do
      get recent_stays_path(source: "reservation")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rémi Direct")          # le séjour reservation est listé
      expect(response.body).not_to include("Tilda Legacy")     # le séjour tally_legacy est filtré
    end
  end
end
