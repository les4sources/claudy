require "rails_helper"

# Issue #99 — Retrait final des écrans d'édition legacy Booking/SpaceBooking.
# Le formulaire d'édition legacy n'existe plus : plus rien ne peut soumettre une
# mise à jour directe. Ce spec PROUVE le retrait des routes `#update` (PATCH/PUT)
# tout en confirmant que les routes d'occupation conservées (show/edit/destroy)
# restent en place.
RSpec.describe "Édition legacy retirée (issue #99)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-issue99@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "routes #update retirées" do
    it "n'expose plus PATCH /bookings/:id" do
      expect { patch "/bookings/1" }.to raise_error(ActionController::RoutingError)
    end

    it "n'expose plus PUT /bookings/:id" do
      expect { put "/bookings/1" }.to raise_error(ActionController::RoutingError)
    end

    it "n'expose plus PATCH /space_bookings/:id" do
      expect { patch "/space_bookings/1" }.to raise_error(ActionController::RoutingError)
    end

    it "n'expose plus PUT /space_bookings/:id" do
      expect { put "/space_bookings/1" }.to raise_error(ActionController::RoutingError)
    end
  end

  describe "routes d'occupation conservées" do
    it "conserve GET /bookings/:id/edit (redirection)" do
      expect(Rails.application.routes.url_helpers).to respond_to(:edit_booking_path)
    end

    it "conserve GET /space_bookings/:id/edit (redirection)" do
      expect(Rails.application.routes.url_helpers).to respond_to(:edit_space_booking_path)
    end

    it "conserve DELETE (destroy) des bookings et space_bookings" do
      helpers = Rails.application.routes.url_helpers
      expect(helpers).to respond_to(:booking_path)
      expect(helpers).to respond_to(:space_booking_path)
    end
  end
end
