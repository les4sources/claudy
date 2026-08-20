require "rails_helper"

# Malau, 2026-08-20 — « quand je confirme une réservation, le client ne reçoit
# plus l'email avec le lien vers sa page ». Cause : depuis le passage stay-first
# (issue #99), plus aucun chemin admin ne déclenchait de notification client.
# Ce spec verrouille les DEUX chemins de confirmation de l'admin, plus le renvoi
# manuel — c'est le contrat de non-régression du bug.
RSpec.describe "Confirmation d'un séjour — email client", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)     { User.create!(email: "accueil@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }
  let(:lodging)  { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  let(:stay) do
    booking = Booking.create!(firstname: "Léa", lastname: "Martin", lodging: lodging,
                              from_date: Date.today + 10, to_date: Date.today + 12,
                              adults: 2, status: "pending", booking_type: "lodging",
                              price_cents: 48_500)
    s = Stay.create!(customer: customer, source: "manual", status: "pending",
                     arrival_date: Date.today + 10, departure_date: Date.today + 12,
                     total_amount_cents: 48_500)
    s.stay_items.create!(bookable: booking)
    s
  end

  def deliveries = ActionMailer::Base.deliveries

  before do
    sign_in user
    deliveries.clear
  end

  describe "PATCH /stays/:id/update_status (action rapide de la modale)" do
    it "envoie au client l'email de confirmation avec le lien de sa page" do
      patch update_status_stay_path(stay, status: "confirmed")

      expect(stay.reload.status).to eq("confirmed")
      expect(deliveries.size).to eq(1)

      mail = deliveries.last
      expect(mail.to).to eq(["guest@example.com"])
      expect(mail.html_part.body.decoded).to include("/sejour/#{stay.token}")
    end

    it "ne renvoie rien sur un aller-retour pending → confirmed → pending → confirmed" do
      patch update_status_stay_path(stay, status: "confirmed")
      patch update_status_stay_path(stay, status: "pending")
      patch update_status_stay_path(stay, status: "confirmed")

      expect(deliveries.size).to eq(1)
    end

    it "n'envoie rien quand le séjour repasse simplement en attente" do
      patch update_status_stay_path(stay, status: "pending")

      expect(deliveries).to be_empty
    end
  end

  describe "POST /stays/:id/send_confirmation_email (renvoi manuel)" do
    it "renvoie l'email même si un premier est déjà parti" do
      patch update_status_stay_path(stay, status: "confirmed")
      expect(deliveries.size).to eq(1)

      post send_confirmation_email_stay_path(stay)

      expect(response).to have_http_status(:found).or have_http_status(:ok)
      expect(deliveries.size).to eq(2)
    end

    it "refuse d'envoyer sur un séjour encore en attente, et le dit" do
      post send_confirmation_email_stay_path(stay)

      expect(deliveries).to be_empty
      expect(flash[:alert]).to include("n'est pas confirmé")
    end
  end

  describe "bouton de renvoi dans la fiche séjour" do
    it "n'apparaît que sur un séjour confirmé d'un client réel" do
      get stay_path(stay)
      expect(response.body).not_to include(send_confirmation_email_stay_path(stay))

      stay.update!(status: "confirmed")
      get stay_path(stay)
      expect(response.body).to include(send_confirmation_email_stay_path(stay))
    end
  end
end
