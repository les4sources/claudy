require "rails_helper"

# Epic #55, Phase 5 — cohérence du rail email de sélection.
# Les réservations d'activités créées par le client via le lien à jeton doivent
# entrer en `pending` (soumises à la validation porteur, Phase 2) et NON
# `confirmed` d'office. Tant qu'elles sont `pending`, elles restent HORS de
# l'exigible (Phase 3) : elles gonflent le total prévu mais pas ce que le client
# doit régler maintenant.
RSpec.describe "Public::ActivitySelections (POST /mon-sejour/:token/activites)", type: :request do
  let(:customer)   { Customer.create!(email: "sel@example.com", customer_type: "individual") }
  let(:stay)       { Stay.create!(customer: customer, status: "pending", arrival_date: Date.today + 20, departure_date: Date.today + 22) }
  let(:porteur)    { Human.create!(name: "Porteuse", email: "porteuse@example.com") }
  let(:experience) { Experience.create!(name: "Balade ânes", human: porteur, fixed_price_cents: 3_000, price_cents: 0) }
  let(:availability) do
    ExperienceAvailability.create!(experience: experience, available_on: Date.today + 21, starts_at: "10:00")
  end

  def post_selection(participants: "2")
    post "/mon-sejour/#{stay.activity_selection_token}/activites",
         params: { activities: { "0" => { availability_id: availability.id, participants: participants } } }
  end

  it "crée les ExperienceBooking en statut pending (validation porteur requise)" do
    expect { post_selection }.to change(ExperienceBooking, :count).by(1)

    eb = ExperienceBooking.last
    expect(eb.stay).to eq(stay)
    expect(eb).to be_pending
    expect(eb).not_to be_confirmed
  end

  it "laisse l'activité pending hors de l'exigible tant qu'elle n'est pas validée" do
    booking = Booking.create!(firstname: "Sel", email: "sel@example.com",
                              from_date: Date.today + 20, to_date: Date.today + 22,
                              adults: 2, status: "confirmed", booking_type: "lodging",
                              price_cents: 40_000)
    stay.stay_items.create!(bookable: booking)

    post_selection
    stay.recompute_aggregates! # total prévu = 40 000 (héberg.) + 3 000 (activité pending)

    expect(stay.experiences_pending_amount_cents).to eq(3_000)
    # Exigible = total prévu − pending → l'activité pending n'entre PAS dans le solde.
    expect(stay.payable_amount_cents).to eq(40_000)
  end
end
