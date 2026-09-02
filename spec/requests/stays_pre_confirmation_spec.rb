require "rails_helper"

# Issue #215 — la pré-confirmation par le Pôle Accueil, côté admin : le bouton
# sur la fiche séjour, l'écran de saisie du montant, l'envoi, et le garde-fou du
# formulaire d'édition (un séjour `pre_confirmed` ne doit pas retomber en
# `pending` à la simple ouverture-enregistrement du form).
RSpec.describe "Stays — pré-confirmation (issue #215)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "accueil@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "guest215@example.com", first_name: "Léa") }
  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def build_stay(status: "pending", customer: nil)
    Stay.create!(customer: customer || self.customer, source: "reservation", status: status,
                 arrival_date: arrival, departure_date: departure, total_amount_cents: 74_500)
  end

  before { ActionMailer::Base.deliveries.clear }

  describe "bouton sur la fiche séjour" do
    it "s'affiche sur une demande en attente d'un client joignable" do
      stay = build_stay

      get stay_path(stay)

      expect(response.body).to include("Pré-confirmer et demander l&#39;acompte")
      expect(response.body).to include(pre_confirm_stay_path(stay))
    end

    it "disparaît une fois le séjour pré-confirmé (pas de second acompte)" do
      stay = build_stay(status: "pre_confirmed")

      get stay_path(stay)

      expect(response.body).not_to include("Pré-confirmer et demander l&#39;acompte")
    end

    it "ne s'affiche pas sur un séjour confirmé" do
      stay = build_stay(status: "confirmed")

      get stay_path(stay)

      expect(response.body).not_to include("Pré-confirmer et demander l&#39;acompte")
    end

    it "ne s'affiche pas pour un client fourre-tout" do
      catch_all = Customer.create!(email: Customer::CATCH_ALL_EMAILS.first, customer_type: "individual")
      stay = build_stay(customer: catch_all)

      get stay_path(stay)

      expect(response.body).not_to include("Pré-confirmer et demander l&#39;acompte")
    end
  end

  describe "GET /stays/:id/pre_confirm" do
    it "montre le total du séjour et prérempli le montant à 50 %" do
      stay = build_stay

      get pre_confirm_stay_path(stay)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("745,00 €")  # total du séjour
      expect(response.body).to include('value="373"') # 50 % arrondi à l'euro
    end
  end

  describe "POST /stays/:id/pre_confirm" do
    it "crée l'acompte, passe le séjour en pre_confirmed et envoie l'email" do
      stay = build_stay

      expect {
        post pre_confirm_stay_path(stay), params: { deposit_amount: "373" }
      }.to change(Payment, :count).by(1)

      expect(response).to redirect_to(stay_path(stay))
      expect(stay.reload.status).to eq("pre_confirmed")
      payment = stay.payments.first
      expect(payment.amount_cents).to eq(37_300)
      expect(payment.status).to eq("pending")
      expect(ActionMailer::Base.deliveries.last.to).to eq(["guest215@example.com"])
    end

    it "accepte un montant ajusté à la virgule (saisie FR)" do
      stay = build_stay

      post pre_confirm_stay_path(stay), params: { deposit_amount: "250,50" }

      expect(stay.reload.payments.first.amount_cents).to eq(25_050)
    end

    it "re-rend l'écran avec une erreur et ne crée RIEN sur un montant invalide" do
      stay = build_stay

      expect {
        post pre_confirm_stay_path(stay), params: { deposit_amount: "0" }
      }.not_to change(Payment, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/supérieur à 0/i)
      expect(stay.reload.status).to eq("pending")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "refuse un montant supérieur au total dû" do
      stay = build_stay

      expect {
        post pre_confirm_stay_path(stay), params: { deposit_amount: "900" }
      }.not_to change(Payment, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/ne peut pas dépasser/i)
    end

    it "refuse un rejeu sur un séjour déjà pré-confirmé" do
      stay = build_stay(status: "pre_confirmed")

      expect {
        post pre_confirm_stay_path(stay), params: { deposit_amount: "373" }
      }.not_to change(Payment, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # LE piège nommé par l'issue : le switch du form ne connaît que
  # pending ↔ confirmed. Sans garde-fou, ouvrir puis enregistrer un séjour
  # pré-confirmé le faisait retomber en `pending` EN SILENCE.
  describe "form d'édition d'un séjour pre_confirmed" do
    def stay_with_booking(status:)
      stay = build_stay(status: status)
      booking = Booking.create!(firstname: "Léa", from_date: arrival, to_date: departure,
                                adults: 2, status: "pending", lodging_id: lodging.id)
      stay.stay_items.create!(bookable: booking)
      stay.reload
    end

    it "rend un select qui inclut le statut courant, présélectionné" do
      stay = stay_with_booking(status: "pre_confirmed")

      get edit_stay_path(stay)

      expect(response.body).to include('name="stay[status]"')
      expect(response.body).to include("Pré-confirmé")
      expect(response.body).to match(/<option selected(="selected")? value="pre_confirmed">/)
    end

    it "laisse le séjour en pre_confirmed quand on enregistre sans y toucher" do
      stay = stay_with_booking(status: "pre_confirmed")

      patch stay_path(stay), params: {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: lodging.id, status: "pre_confirmed"
        }
      }

      expect(stay.reload.status).to eq("pre_confirmed")
    end

    it "garde le switch à deux états sur un séjour pending (comportement historique)" do
      stay = stay_with_booking(status: "pending")

      get edit_stay_path(stay)

      expect(response.body).to include('id="stay_status_toggle"')
      expect(response.body).not_to include("Pré-confirmé")
    end
  end

  describe "badge de statut" do
    it "affiche « Pré-confirmé » sur la fiche séjour, sans retomber sur le gris par défaut" do
      stay = build_stay(status: "pre_confirmed")

      get stay_path(stay)

      expect(response.body).to include("Pré-confirmé")
      expect(response.body).to include("bg-indigo-100 text-indigo-800")
    end

    it "affiche « Pré-confirmé » sur /stays/recents" do
      build_stay(status: "pre_confirmed")

      get recent_stays_path

      expect(response.body).to include("Pré-confirmé")
    end
  end
end
