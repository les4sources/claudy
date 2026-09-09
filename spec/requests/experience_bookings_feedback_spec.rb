require "rails_helper"

# Bug du 2026-09-08 : « je clique sur OK sur l'activité d'un séjour, dans la
# modale séjour, et il ne se passe rien ».
#
# Le formulaire vit dans le turbo-frame des activités et le contrôleur répond en
# Turbo Stream. Un succès remplaçait la frame par un contenu identique (aucun
# retour), et les échecs — validation, activité d'un autre porteur, créneau
# introuvable — répondaient `head 422/404` SANS corps : Turbo n'affichait rien.
# Toute réponse Turbo Stream porte désormais son message dans la frame.
RSpec.describe "ExperienceBookings — retour visible dans la modale séjour", type: :request do
  include Devise::Test::IntegrationHelpers

  TURBO = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  let(:customer) { Customer.create!(email: "retour@example.com", customer_type: "individual") }
  let(:stay)     { Stay.create!(customer: customer, arrival_date: Date.today + 20, departure_date: Date.today + 22) }

  let(:porteur_a) { Human.create!(name: "Porteuse A", email: "a@example.com") }
  let(:user_a)    { User.create!(email: "a@example.com", password: "password123", human: porteur_a) }
  let(:exp_a)     { Experience.create!(name: "Balade ânes", human: porteur_a, fixed_price_cents: 4000, price_cents: 1500) }
  let(:avail_a)   { ExperienceAvailability.create!(experience: exp_a, available_on: Date.today + 21, starts_at: "10:00") }

  let(:porteur_b) { Human.create!(name: "Porteur B", email: "b@example.com") }
  let(:user_b)    { User.create!(email: "b@example.com", password: "password123", human: porteur_b) }
  let(:exp_b)     { Experience.create!(name: "Poterie", human: porteur_b, price_cents: 2000) }
  let(:avail_b)   { ExperienceAvailability.create!(experience: exp_b, available_on: Date.today + 21, starts_at: "14:00") }

  # Compte accueil (sans `human`) = admin global.
  let(:admin) { User.create!(email: "staff@les4sources.be", password: "password123") }

  let(:frame) { "stay_#{stay.id}_activities" }

  describe "PATCH (bouton OK)" do
    let!(:booking) { ExperienceBooking.create!(experience_availability: avail_a, stay: stay, participants: 2, status: "pending") }

    it "confirme l'enregistrement dans la frame, même quand rien ne change à l'écran" do
      sign_in admin
      patch experience_booking_path(booking), params: { experience_booking: { participants: 2 } }, headers: TURBO

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(frame)
      expect(response.body).to include("Nombre de participants enregistré : 2.")
      expect(response.body).to include('role="status"')
    end

    it "affiche l'erreur de validation dans la frame au lieu d'un 422 muet" do
      sign_in admin
      patch experience_booking_path(booking), params: { experience_booking: { participants: "" } }, headers: TURBO

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(frame)
      expect(response.body).to include('role="alert"')
      expect(booking.reload.participants).to eq(2)
    end

    it "explique à un porteur qu'il ne peut pas modifier l'activité d'un autre porteur" do
      target = ExperienceBooking.create!(experience_availability: avail_b, stay: stay, participants: 1, status: "pending")
      sign_in user_a
      patch experience_booking_path(target), params: { experience_booking: { participants: 9 } }, headers: TURBO

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(frame)
      expect(response.body).to include("portée par quelqu&#39;un d&#39;autre")
      expect(target.reload.participants).to eq(1)
    end

    # Le compte cloisonné n'a pas accès à la fiche séjour : le panneau, qui porte
    # le total du séjour, l'encaissé et le solde dû, ne doit jamais lui parvenir —
    # pas même par un appel direct en Turbo Stream.
    it "ne livre RIEN du séjour à un compte cloisonné" do
      restreint = User.create!(email: "cloisonne@example.com", password: "password123",
                               human: porteur_a, restricted_to_experiences: true)
      target = ExperienceBooking.create!(experience_availability: avail_b, stay: stay, participants: 1, status: "pending")
      sign_in restreint
      patch experience_booking_path(target), params: { experience_booking: { participants: 9 } }, headers: TURBO

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
      expect(target.reload.participants).to eq(1)
    end

    it "reste un 404 nu pour un id inexistant" do
      sign_in admin
      patch experience_booking_path(id: 999_999), params: { experience_booking: { participants: 3 } }, headers: TURBO

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
    end

    it "sert toujours la redirection HTML aux clients sans Turbo" do
      sign_in admin
      patch experience_booking_path(booking), params: { experience_booking: { participants: 4 } }

      expect(response).to redirect_to(stay_path(stay))
      expect(booking.reload.participants).to eq(4)
    end
  end

  describe "POST (Ajouter l'activité)" do
    before { sign_in admin }

    it "confirme l'ajout dans la frame" do
      post stay_experience_bookings_path(stay),
           params: { experience_booking: { experience_availability_id: avail_a.id, participants: 2, status: "pending" } },
           headers: TURBO

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ajoutée au séjour")
    end

    it "affiche l'erreur dans la frame quand l'ajout est invalide" do
      post stay_experience_bookings_path(stay),
           params: { experience_booking: { experience_availability_id: avail_a.id, participants: 0, status: "pending" } },
           headers: TURBO

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(frame)
      expect(response.body).to include('role="alert"')
      expect(stay.experience_bookings.count).to eq(0)
    end

    it "dit que le créneau est introuvable au lieu d'un 404 muet" do
      post stay_experience_bookings_path(stay),
           params: { experience_booking: { experience_availability_id: 999_999, participants: 1, status: "pending" } },
           headers: TURBO

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(frame)
      expect(response.body).to include("Créneau introuvable.")
    end
  end

  describe "DELETE (Retirer)" do
    it "confirme le retrait dans la frame" do
      booking = ExperienceBooking.create!(experience_availability: avail_a, stay: stay, participants: 2, status: "confirmed")
      sign_in admin
      delete experience_booking_path(booking), headers: TURBO

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("retirée du séjour")
      expect(booking.reload.status).to eq("cancelled")
    end
  end
end
