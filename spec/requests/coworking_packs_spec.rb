require "rails_helper"

# Epic #126, Phase 1 — admin des packs de coworking.
RSpec.describe "Coworking (admin)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }
  let(:monday) { Date.new(2026, 9, 7) }

  before { sign_in user }

  describe "GET /coworking_packs" do
    it "liste les packs avec jours restants, expiration et badge paiement" do
      pack = CoworkingPack.create!(customer: customer, days_total: 10, payment_method: "card")
      pack.coworking_reservations.create!(date: monday)

      get coworking_packs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Coworking")
      expect(response.body).to include("Ana")
      expect(response.body).to include("non payé")
      # 9 journées restantes sur 10
      expect(response.body).to include("/ 10")
    end
  end

  describe "POST /coworking_packs" do
    it "crée un pack payé par carte, sans paiement en attente" do
      expect {
        post coworking_packs_path, params: {
          coworking_pack: { customer_id: customer.id, days_total: 5, payment_method: "card" }
        }
      }.to change(CoworkingPack, :count).by(1)

      pack = CoworkingPack.last
      expect(pack.price_cents).to eq(8_000)
      expect(pack.payments).to be_empty
      expect(response).to redirect_to(coworking_pack_path(pack))
    end

    it "crée un Payment en attente pour un virement" do
      post coworking_packs_path, params: {
        coworking_pack: { customer_id: customer.id, days_total: 20, payment_method: "bank_transfer" }
      }

      pack = CoworkingPack.last
      expect(pack.payments.count).to eq(1)
      payment = pack.payments.first
      expect(payment.status).to eq("pending")
      expect(payment.amount_cents).to eq(30_000)
      expect(payment.stay_id).to be_nil
      expect(pack.payment_status).to eq("pending")
    end

    it "refuse une taille de pack hors barème" do
      expect {
        post coworking_packs_path, params: {
          coworking_pack: { customer_id: customer.id, days_total: 3, payment_method: "cash" }
        }
      }.not_to change(CoworkingPack, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "journées d'un pack" do
    let(:pack) { CoworkingPack.create!(customer: customer, days_total: 5, payment_method: "card") }

    it "pose une journée" do
      expect {
        post coworking_pack_coworking_reservations_path(pack),
             params: { coworking_reservation: { date: monday.to_s } }
      }.to change { pack.coworking_reservations.count }.by(1)

      expect(response).to redirect_to(coworking_pack_path(pack))
    end

    it "refuse un week-end avec un message et sans rien créer" do
      expect {
        post coworking_pack_coworking_reservations_path(pack),
             params: { coworking_reservation: { date: (monday + 5).to_s } }
      }.not_to change { pack.coworking_reservations.count }

      follow_redirect!
      expect(response.body).to include("lundi à vendredi")
    end

    it "refuse un 4e bureau le même jour" do
      3.times do
        other = CoworkingPack.create!(
          customer: Customer.create!(first_name: "X", last_name: SecureRandom.hex(3), email: "#{SecureRandom.hex(4)}@example.com"),
          days_total: 5, payment_method: "card"
        )
        other.coworking_reservations.create!(date: monday)
      end

      expect {
        post coworking_pack_coworking_reservations_path(pack),
             params: { coworking_reservation: { date: monday.to_s } }
      }.not_to change { pack.coworking_reservations.count }

      follow_redirect!
      expect(response.body).to include("complet")
    end

    it "annule une journée en douceur et rend le crédit" do
      reservation = pack.coworking_reservations.create!(date: monday)

      delete coworking_pack_coworking_reservation_path(pack, reservation)

      expect(pack.reload.days_remaining).to eq(5)
      expect(CoworkingReservation.unscoped.find(reservation.id).deleted_at).to be_present
    end

    it "supprime le pack en douceur" do
      delete coworking_pack_path(pack)

      expect(CoworkingPack.where(id: pack.id)).to be_empty
      expect(response).to redirect_to(coworking_packs_path)
    end
  end

  describe "sans authentification" do
    it "redirige vers la connexion" do
      sign_out user
      get coworking_packs_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
