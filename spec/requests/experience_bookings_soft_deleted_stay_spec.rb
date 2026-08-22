require "rails_helper"

# Epic #55 — régression trouvée à la passe navigateur du 2026-08-21.
#
# Supprimer un séjour est une suppression DOUCE : `dependent: :destroy` ne se
# déclenche pas, ses `ExperienceBooking` survivent, et le `default_scope` de
# `soft_deletion` fait ensuite renvoyer `nil` à `booking.stay`. La page de
# validation, qui affiche le client du séjour, plantait alors en 500 — pour TOUS
# les porteurs, à cause d'une seule réservation orpheline. Trois de ces
# orphelines existaient en production.
RSpec.describe "ExperienceBookings — séjour supprimé", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:customer) { Customer.create!(email: "orphelin@example.com", customer_type: "individual") }
  let(:porteur)  { Human.create!(name: "Porteuse", email: "porteuse@example.com") }
  let(:user)     { User.create!(email: "porteuse@example.com", password: "password123", human: porteur) }
  let(:admin)    { User.create!(email: "staff@les4sources.be", password: "password123") }
  let(:experience) { Experience.create!(name: "Vannerie", human: porteur, fixed_price_cents: 5000, price_cents: 1500) }
  let(:availability) { ExperienceAvailability.create!(experience: experience, available_on: Date.today + 10, starts_at: "10:00") }

  let!(:vivant) do
    stay = Stay.create!(customer: customer, arrival_date: Date.today + 9, departure_date: Date.today + 12)
    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "pending")
  end

  # On marque `deleted_at` DIRECTEMENT, sans passer par `destroy` : c'est l'état
  # observé en production (trois réservations survivantes). `Stay#destroy`
  # déclenche le `dependent: :destroy` et emporte les activités avec lui, mais
  # tout autre chemin de suppression douce les laisse derrière.
  let!(:orphelin) do
    stay = Stay.create!(customer: customer, arrival_date: Date.today + 30, departure_date: Date.today + 32)
    booking = ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "pending")
    stay.update_column(:deleted_at, Time.current)
    booking
  end

  it "rend l'index sans planter et n'y liste pas l'activité orpheline" do
    sign_in admin
    get experience_bookings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Activités réservées")
  end

  it "écarte l'orpheline de la portée d'un porteur comme d'un admin" do
    expect(ExperienceBooking.for_user(admin)).to include(vivant)
    expect(ExperienceBooking.for_user(admin)).not_to include(orphelin)
    expect(ExperienceBooking.for_user(user)).not_to include(orphelin)
  end

  it "répond 404 plutôt que 500 sur une action ciblant une orpheline" do
    sign_in admin
    patch confirm_experience_booking_path(orphelin)

    expect(response).not_to have_http_status(:internal_server_error)
    expect(orphelin.reload.status).to eq("pending")
  end
end
