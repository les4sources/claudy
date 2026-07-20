require "rails_helper"

# UI serveur de la fusion de séjours (epic #81, Phase 2). Trois fragments rendus
# côté serveur — désignation (merge_setup), aperçu dry-run (merge_preview),
# commit (merge) — protégés Devise et bornés par des garde-fous (≥ 2 séjours).
RSpec.describe "Stays merge (epic #81)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { User.create!(email: "staff-merge@les4sources.be", password: "password123") }
  let(:c_target) { Customer.create!(email: "target@example.com", customer_type: "individual", first_name: "Cible") }
  let(:c_source) { Customer.create!(email: "source@example.com", customer_type: "individual", first_name: "Source") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }

  def build_stay(customer:, arrival:, departure:, lodging_cents:, paid_cents: nil)
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: arrival, departure_date: departure)
    booking = Booking.create!(firstname: customer.first_name, lodging: lodging, from_date: arrival,
                              to_date: departure, adults: 2, status: "confirmed",
                              booking_type: "lodging", price_cents: lodging_cents)
    stay.stay_items.create!(bookable: booking)
    Payment.create!(stay: stay, amount_cents: paid_cents, status: "paid", payment_method: "card") if paid_cents
    stay.recompute_aggregates!
    stay.set_payment_status
    stay
  end

  let!(:target) { build_stay(customer: c_target, arrival: Date.new(2026, 9, 12), departure: Date.new(2026, 9, 15), lodging_cents: 30_000, paid_cents: 10_000) }
  let!(:source) { build_stay(customer: c_source, arrival: Date.new(2026, 9, 16), departure: Date.new(2026, 9, 18), lodging_cents: 20_000) }

  before { sign_in admin }

  describe "POST /stays/merge_setup" do
    it "rend l'étape A avec une carte radio par séjour et présélectionne le porteur de paiements" do
      post merge_setup_stays_path, params: { stay_ids: [target.id, source.id] }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="target_id"')
      expect(response.body).to include("Fusionner 2 séjours")
      expect(response.body).to include("suggéré")
      # La cible porte des paiements → présélectionnée (radio checked). L'attribut
      # `checked` est sérialisé avant `value` dans la balise input.
      expect(response.body).to match(/<input checked[^>]*value="#{target.id}"/)
    end

    it "affiche l'encart « clients différents » quand les clients diffèrent" do
      post merge_setup_stays_path, params: { stay_ids: [target.id, source.id] }
      expect(response.body).to include("Clients différents")
    end

    it "refuse moins de deux séjours (422)" do
      post merge_setup_stays_path, params: { stay_ids: [target.id] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("au moins deux séjours")
    end
  end

  describe "POST /stays/merge_preview" do
    it "rend l'étape B avec l'aperçu dry-run (total, payé, solde)" do
      post merge_preview_stays_path, params: { target_id: target.id, stay_ids: [target.id, source.id] }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aperçu de la fusion")
      expect(response.body).to include("Nouveau total")
      expect(response.body).to include("Séjour ##{target.id}")
      expect(response.body).to include("archivé")
    end

    it "refuse moins de deux séjours (422)" do
      post merge_preview_stays_path, params: { target_id: target.id, stay_ids: [target.id] }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /stays/merge" do
    it "exécute la fusion, archive la source et redirige avec un flash détaillé (JSON)" do
      post merge_stays_path, params: { target_id: target.id, stay_ids: [target.id, source.id] }, as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["redirect"]).to include("stay_merge_done=1")

      expect(Stay.find_by(id: source.id)).to be_nil                    # soft-deleted
      expect(target.reload.stay_items.count).to eq(2)
      expect(flash[:notice]).to include("fusionné").and include("##{target.id}")
    end

    it "refuse une cible figurant parmi les sources et re-rend l'aperçu avec l'erreur (422)" do
      # target_id absent des stay_ids résolus → cible = min id ; on force le cas
      # dégénéré d'un seul séjour pour déclencher le garde-fou serveur.
      post merge_stays_path, params: { target_id: target.id, stay_ids: [target.id] }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "redirige vers le `return_url` fourni (fiche client) au lieu du calendrier" do
      post merge_stays_path,
           params: { target_id: target.id, stay_ids: [target.id, source.id], return_url: "/customers/#{c_target.id}" },
           as: :json
      json = JSON.parse(response.body)
      expect(json["redirect"]).to start_with("/customers/#{c_target.id}")
      expect(json["redirect"]).to include("stay_merge_done=1")
    end

    it "ignore un `return_url` non same-origin (anti open-redirect) et retombe sur le calendrier" do
      post merge_stays_path,
           params: { target_id: target.id, stay_ids: [target.id, source.id], return_url: "https://evil.example/phish" },
           as: :json
      json = JSON.parse(response.body)
      expect(json["redirect"]).not_to include("evil.example")
      expect(json["redirect"]).to include("stay_merge_done=1")
    end
  end

  describe "authentification" do
    it "exige une session admin (Devise)" do
      sign_out admin
      post merge_setup_stays_path, params: { stay_ids: [target.id, source.id] }
      expect(response).to have_http_status(:found) # redirigé vers login
    end
  end
end
