require "rails_helper"

# Épic #81, Phase 9 (finale) — dépréciation effective de la création directe.
# Le séjour (`resources :stays`) et le funnel natif `/reservation` sont désormais
# les SEULS points d'entrée de création. Ce spec PROUVE le retrait : les anciennes
# routes de création directe (admin + public legacy) n'existent plus, tandis que
# les routes d'occupation (index/show/edit/update/destroy) et les services client
# token (edit_estimated_arrival) restent en place.
RSpec.describe "Création directe retirée (epic #81, Phase 9)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-phase9@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "création directe admin — routes retirées" do
    it "n'a plus d'action #new dédiée pour bookings (/bookings/new retombe sur #show id=new)" do
      # `new` n'étant plus une action, /bookings/new est interprété comme #show
      # avec id="new" → introuvable. Preuve qu'aucun formulaire de création n'est servi.
      expect { get "/bookings/new" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "n'expose plus POST /bookings" do
      expect { post "/bookings" }.to raise_error(ActionController::RoutingError)
    end

    it "n'a plus d'action #new dédiée pour space_bookings (/space_bookings/new retombe sur #show id=new)" do
      expect { get "/space_bookings/new" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "n'expose plus POST /space_bookings" do
      expect { post "/space_bookings" }.to raise_error(ActionController::RoutingError)
    end

    it "ne fournit plus les helpers new_booking_path / new_space_booking_path" do
      helpers = Rails.application.routes.url_helpers
      expect(helpers).not_to respond_to(:new_booking_path)
      expect(helpers).not_to respond_to(:new_space_booking_path)
    end
  end

  describe "demande de réservation publique legacy — routes retirées" do
    it "n'expose plus GET /public/bookings/new" do
      expect { get "/public/bookings/new" }.to raise_error(ActionController::RoutingError)
    end

    it "n'expose plus POST /public/bookings" do
      expect { post "/public/bookings" }.to raise_error(ActionController::RoutingError)
    end

    it "ne fournit plus le helper new_public_booking_path" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:new_public_booking_path)
    end
  end

  describe "routes d'occupation conservées (fallback orphelin + consultation)" do
    it "sert toujours l'index des bookings" do
      get "/bookings"
      expect(response).to have_http_status(:ok)
    end

    it "sert toujours l'index des space_bookings" do
      get "/space_bookings"
      expect(response).to have_http_status(:ok)
    end

    it "conserve le helper membre edit_estimated_arrival_public_booking_path (service client)" do
      expect(Rails.application.routes.url_helpers)
        .to respond_to(:edit_estimated_arrival_public_booking_path)
    end

    it "conserve le funnel natif public_reservation_start (nouveau point d'entrée public)" do
      expect(Rails.application.routes.url_helpers).to respond_to(:public_reservation_start_path)
    end
  end
end
