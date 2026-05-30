require "rails_helper"

RSpec.describe "Vue admin — Stays récents (/sejours/recents)", type: :request do
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

    let!(:reservation_stay) do
      Stay.create!(customer: customer, source: "reservation", status: "pending",
                   arrival_date: Date.today + 3, departure_date: Date.today + 5)
    end
    let!(:tally_stay) do
      Stay.create!(customer: customer, source: "tally_legacy", status: "confirmed",
                   arrival_date: Date.today + 10, departure_date: Date.today + 12)
    end

    it "liste tous les séjours sans filtre" do
      get recent_stays_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("reservation")
      expect(response.body).to include("tally_legacy")
    end

    it "restreint la liste au canal demandé" do
      get recent_stays_path(source: "reservation")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(reservation_stay.id.to_s)
      expect(response.body).not_to include(">#{tally_stay.id}<")
    end
  end
end
