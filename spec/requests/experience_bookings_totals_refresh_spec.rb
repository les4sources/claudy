require "rails_helper"

# Epic #55, Phase 6 — régression trouvée à la passe navigateur du 2026-08-21.
#
# L'AC « impact immédiat sur `total_amount_cents` » était vrai EN BASE et faux
# À L'ÉCRAN : le formulaire d'ajout vit dans le turbo-frame des activités, et un
# `redirect_to stay_path` ne remplace que la frame d'où part la soumission.
# L'admin voyait sa nouvelle activité apparaître au-dessus d'un « Total séjour »
# et d'un « Solde dû » restés sur leurs anciens montants — l'écran contredisait
# la base jusqu'au rechargement suivant. Les mutations répondent désormais en
# Turbo Stream et rafraîchissent les deux panneaux.
RSpec.describe "ExperienceBookings — rafraîchissement des montants", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:customer) { Customer.create!(email: "refresh@example.com", customer_type: "individual") }
  let(:admin)    { User.create!(email: "staff@les4sources.be", password: "password123") }
  let(:porteur)  { Human.create!(name: "Porteuse", email: "porteuse@example.com") }
  let(:experience) { Experience.create!(name: "Vannerie", human: porteur, fixed_price_cents: 5_000, price_cents: 1_500) }
  let(:availability) { ExperienceAvailability.create!(experience: experience, available_on: Date.today + 21, starts_at: "10:00") }

  let(:stay) do
    s = Stay.create!(customer: customer, status: "confirmed",
                     arrival_date: Date.today + 20, departure_date: Date.today + 22)
    booking = Booking.create!(firstname: "Rafra", lastname: "Îchir", from_date: Date.today + 20,
                              to_date: Date.today + 22, adults: 2, status: "confirmed",
                              booking_type: "lodging", price_cents: 60_000)
    s.stay_items.create!(bookable: booking)
    s.recompute_aggregates!
    s
  end

  before { sign_in admin }

  # 5 000 + 1 500 × 2 = 8 000 → total 68 000.
  def add_activity(status: "confirmed", participants: 2)
    post stay_experience_bookings_path(stay),
         params: { experience_booking: { experience_availability_id: availability.id,
                                         participants: participants, status: status } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  it "renvoie les deux panneaux, montants à jour, à l'ajout" do
    add_activity

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("stay_#{stay.id}_activities")
    expect(response.body).to include("stay_#{stay.id}_payments")
    expect(stay.reload.total_amount_cents).to eq(68_000)
    expect(response.body).to include("680") # « Total séjour » recalculé dans la réponse
  end

  it "rafraîchit aussi les montants au retrait" do
    add_activity
    booking = stay.experience_bookings.order(:id).last

    delete experience_booking_path(booking), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("stay_#{stay.id}_payments")
    expect(stay.reload.total_amount_cents).to eq(60_000)
  end

  it "rafraîchit les montants à l'édition du nombre de participants" do
    add_activity
    booking = stay.experience_bookings.order(:id).last

    patch experience_booking_path(booking),
          params: { experience_booking: { participants: 5 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("stay_#{stay.id}_payments")
    # 5 000 + 1 500 × 5 = 12 500 → 60 000 + 12 500.
    expect(stay.reload.total_amount_cents).to eq(72_500)
  end

  it "sert toujours la redirection HTML aux clients sans Turbo" do
    post stay_experience_bookings_path(stay),
         params: { experience_booking: { experience_availability_id: availability.id,
                                         participants: 2, status: "confirmed" } }

    expect(response).to redirect_to(stay_path(stay))
  end
end
