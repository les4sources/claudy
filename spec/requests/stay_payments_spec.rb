require "rails_helper"

# Gestion des paiements d'un séjour DEPUIS sa modale (StayPaymentsController) :
# la secrétaire ajoute un paiement et bascule son statut (pending → paid) sans
# quitter la modale. Après chaque mutation, le séjour recalcule son
# `payment_status` (adossé à l'EXIGIBLE) : dès que l'encaissé couvre le total, il
# passe à « paid ». Toutes les routes exigent une session Devise.
RSpec.describe "Stay payments (modale séjour)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { User.create!(email: "staff-stay-pay@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(email: "stay-pay@example.com", customer_type: "individual", first_name: "Ada", last_name: "Lovelace") }

  let(:from) { Date.today + 30 }
  let(:to)   { Date.today + 32 }

  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: from, departure_date: to, total_amount_cents: 10_000,
                 payment_status: "pending")
  end

  describe "auth Devise requise" do
    it "redirige la création vers la connexion quand non authentifié" do
      post stay_payments_path(stay), params: { payment: { amount: 50, payment_method: "cash", status: "paid" } }
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirige la mise à jour vers la connexion quand non authentifié" do
      payment = Payment.create!(stay: stay, amount_cents: 5_000, payment_method: "cash", status: "pending")
      patch stay_payment_path(stay, payment), params: { payment: { status: "paid" } }
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  context "authentifié" do
    before { sign_in admin }

    describe "ajout d'un paiement" do
      it "crée le paiement rattaché au séjour et redirige vers la fiche" do
        expect {
          post stay_payments_path(stay), params: { payment: { amount: 40, payment_method: "bank_transfer", status: "pending" } }
        }.to change { stay.direct_payments.count }.by(1)

        expect(response).to redirect_to(stay_path(stay))

        payment = stay.direct_payments.order(:created_at).last
        expect(payment.amount_cents).to eq(4_000)
        expect(payment.payment_method).to eq("bank_transfer")
        expect(payment.status).to eq("pending")
      end

      it "rejette un montant invalide (pas de création)" do
        expect {
          post stay_payments_path(stay), params: { payment: { amount: 0, payment_method: "cash", status: "paid" } }
        }.not_to change { Payment.count }
        expect(response).to redirect_to(stay_path(stay))
      end
    end

    describe "changement de statut d'un paiement" do
      let!(:payment) { Payment.create!(stay: stay, amount_cents: 3_000, payment_method: "cash", status: "pending") }

      it "bascule pending → paid" do
        patch stay_payment_path(stay, payment), params: { payment: { status: "paid" } }
        expect(response).to redirect_to(stay_path(stay))
        expect(payment.reload.status).to eq("paid")
      end
    end

    describe "passage automatique du séjour à « paid »" do
      it "bascule le séjour en paid quand la somme des paiements paid couvre le total" do
        # total = 100 € : un premier paiement partiel ne suffit pas…
        post stay_payments_path(stay), params: { payment: { amount: 40, payment_method: "cash", status: "paid" } }
        expect(stay.reload.payment_status).to eq("partially_paid")

        # …le solde encaissé fait basculer le séjour en « paid ».
        post stay_payments_path(stay), params: { payment: { amount: 60, payment_method: "bank_transfer", status: "paid" } }
        expect(stay.reload.payment_status).to eq("paid")
      end

      it "un paiement en attente ne solde pas le séjour" do
        post stay_payments_path(stay), params: { payment: { amount: 100, payment_method: "bank_transfer", status: "pending" } }
        expect(stay.reload.payment_status).to eq("pending")
      end

      it "basculer un paiement pending → paid solde le séjour" do
        payment = Payment.create!(stay: stay, amount_cents: 10_000, payment_method: "bank_transfer", status: "pending")
        expect(stay.reload.payment_status).to eq("pending")

        patch stay_payment_path(stay, payment), params: { payment: { status: "paid" } }
        expect(stay.reload.payment_status).to eq("paid")
      end
    end
  end
end
