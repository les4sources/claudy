require "rails_helper"

RSpec.describe "Stays (détails admin)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-stays@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "stayshow@example.com", customer_type: "individual") }
  let(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 2, 14),
                 departure_date: Date.new(2026, 2, 15), status: "confirmed", total_amount_cents: 12_000)
  end
  let!(:booking) do
    Booking.create!(firstname: "Jean", lastname: "Dupont", group_name: "Les Amis",
                    from_date: Date.new(2026, 2, 14), to_date: Date.new(2026, 2, 15),
                    adults: 2, status: "confirmed")
  end

  before { stay.stay_items.create!(bookable: booking) }

  describe "GET /stays/:id" do
    it "renders the stay details fragment with French dates and contact" do
      get stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Séjour ##{stay.id}")
      expect(response.body).to include("14 février 2026")
      expect(response.body).to include("Jean Dupont")
      expect(response.body).to include("Les Amis")
      expect(response.body).to include("Confirmé") # statut en label
    end
  end
end
