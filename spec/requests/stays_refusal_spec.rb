require "rails_helper"

# Écran de refus d'une demande (décision Michael du 2026-09-08). Le service est
# couvert par `spec/services/stays/refuser_spec.rb` ; ici on verrouille le
# CÂBLAGE admin : le bouton n'apparaît que là où il a un sens, l'écran s'ouvre,
# un motif vide ne passe pas, et un refus valide redirige avec le bon message.
RSpec.describe "Séjours — refus d'une demande", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "refus-admin@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre H", level: 1)
    l
  end

  let(:arrivee) { Date.today + 30 }
  let(:depart)  { Date.today + 32 }

  def demande(status: "pending")
    stay = Stay.create!(customer: customer, source: "reservation", status: status,
                        arrival_date: arrivee, departure_date: depart,
                        total_amount_cents: 74_500)
    booking = Booking.create!(firstname: "Léa", from_date: arrivee, to_date: depart,
                              adults: 2, status: status, lodging: hulotte)
    hulotte.rooms.each do |room|
      (arrivee...depart).each { |d| Reservation.create!(booking: booking, room: room, date: d) }
    end
    stay.stay_items.create!(bookable: booking)
    stay.reload
  end

  describe "bouton sur la fiche séjour" do
    it "s'affiche sur une demande EN ATTENTE" do
      stay = demande(status: "pending")

      get stay_path(stay)

      expect(response.body).to include(refuse_stay_path(stay))
      expect(response.body).to include("Refuser la demande")
    end

    # C'est là qu'il est le plus utile : le séjour bloque des dates à rendre.
    it "s'affiche aussi sur une demande PRÉ-CONFIRMÉE" do
      stay = demande(status: "pre_confirmed")

      get stay_path(stay)

      expect(response.body).to include(refuse_stay_path(stay))
    end

    it "disparaît sur un séjour CONFIRMÉ (celui-là s'annule, il ne se refuse pas)" do
      stay = demande(status: "confirmed")

      get stay_path(stay)

      expect(response.body).not_to include(refuse_stay_path(stay))
    end

    it "disparaît sur un séjour déjà annulé" do
      stay = demande(status: "canceled")

      get stay_path(stay)

      expect(response.body).not_to include(refuse_stay_path(stay))
    end
  end

  describe "GET /stays/:id/refuse" do
    it "rend l'écran avec le rappel du séjour et le champ motif" do
      stay = demande

      get refuse_stay_path(stay)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Refuser la demande ##{stay.id}")
      expect(response.body).to include("refusal_reason")
      expect(response.body).to include("Motif (envoyé au client)")
    end

    it "prévient AVANT le clic quand le client n'est pas joignable" do
      stay = demande
      stay.customer.update!(email: nil)

      get refuse_stay_path(stay)

      expect(response.body).to include("AUCUN message ne partira")
    end
  end

  describe "POST /stays/:id/refuse" do
    it "sans motif : 422, l'écran est re-rendu et le séjour ne bouge pas" do
      stay = demande

      post refuse_stay_path(stay), params: { refusal_reason: "   " }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("refusal_reason")
      expect(stay.reload.status).to eq("pending")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "avec motif : redirige vers la fiche, annule le séjour et prévient le client" do
      ActionMailer::Base.deliveries.clear
      stay = demande(status: "pre_confirmed")
      stay.bookables.each { |b| b.update!(status: "pre_confirmed") }

      post refuse_stay_path(stay), params: { refusal_reason: "Le gîte est déjà pris." }

      expect(response).to redirect_to(stay_path(stay))
      expect(flash[:notice]).to include("Demande refusée")
      expect(flash[:notice]).to include("guest@example.com")
      expect(stay.reload.status).to eq("canceled")
      # Les dates sont rendues : c'est tout l'intérêt de refuser tôt.
      expect(hulotte.reload.available_between?(arrivee, depart)).to be(true)
      expect(ActionMailer::Base.deliveries.last.to).to eq(["guest@example.com"])
    end

    it "dit clairement qu'aucun email n'est parti pour un client sans adresse" do
      stay = demande
      stay.customer.update!(email: nil)

      post refuse_stay_path(stay), params: { refusal_reason: "Complet." }

      expect(response).to redirect_to(stay_path(stay))
      expect(flash[:alert]).to include("AUCUN email")
      expect(stay.reload.status).to eq("canceled")
    end

    it "refuse un séjour confirmé avec un message explicite" do
      stay = demande(status: "confirmed")

      post refuse_stay_path(stay), params: { refusal_reason: "Trop tard." }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(stay.reload.status).to eq("confirmed")
    end
  end
end
