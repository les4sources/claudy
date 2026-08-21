require "rails_helper"

# Décision Michael 2026-08-21 : quand l'équipe ajoute elle-même une activité
# DÉJÀ VALIDÉE sur un séjour, elle entre aussitôt dans le solde dû — le client
# l'apprend par mail. Ajoutée « à valider », elle suit le flux du porteur, dont
# la validation porte déjà sa propre notification : pas de doublon.
RSpec.describe "ExperienceBookings — notification d'ajout admin", type: :request, queue_adapter: :test do
  include Devise::Test::IntegrationHelpers

  let(:customer)   { Customer.create!(email: "prevenu@example.com", customer_type: "individual") }
  let(:stay)       { Stay.create!(customer: customer, arrival_date: Date.today + 20, departure_date: Date.today + 22) }
  let(:admin)      { User.create!(email: "staff@les4sources.be", password: "password123") }
  let(:experience) { Experience.create!(name: "Vannerie", fixed_price_cents: 5_000, price_cents: 1_500) }
  let(:slot)       { ExperienceAvailability.create!(experience: experience, available_on: Date.today + 21, starts_at: "10:00") }

  before { sign_in admin }

  def add(status)
    post stay_experience_bookings_path(stay),
         params: { experience_booking: { experience_availability_id: slot.id,
                                         participants: 2, status: status } }
  end

  it "prévient le client d'une activité ajoutée déjà validée" do
    expect { add("confirmed") }
      .to have_enqueued_mail(ActivitySelectionMailer, :booking_added_by_team)
  end

  it "ne lui écrit pas pour une activité ajoutée à valider" do
    expect { add("pending") }
      .not_to have_enqueued_mail(ActivitySelectionMailer, :booking_added_by_team)
  end

  it "annonce le créneau, les participants et le montant" do
    add("confirmed")
    booking = stay.experience_bookings.order(:id).last
    mail = ActivitySelectionMailer.booking_added_by_team(booking)

    expect(mail.to).to eq([customer.email])
    expect(mail.subject).to include("Vannerie")
    # 5 000 + 1 500 × 2 = 8 000.
    expect(mail.body.encoded).to include("80 €")
    expect(mail.body.encoded).to include("2")
  end
end
