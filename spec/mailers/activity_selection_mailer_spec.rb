require "rails_helper"

# Epic #55 — Phase 2 : notifications client (validation/refus) + liens porteur.
RSpec.describe ActivitySelectionMailer, type: :mailer do
  let(:customer)   { Customer.create!(email: "client@example.com", first_name: "Léa", customer_type: "individual") }
  let(:stay)       { Stay.create!(customer: customer, arrival_date: Date.today + 20, departure_date: Date.today + 22) }
  let(:porteur)    { Human.create!(name: "Porteuse Balade", email: "porteuse@example.com") }
  let(:experience) { Experience.create!(name: "Balade avec les ânes", human: porteur) }
  let(:availability) do
    ExperienceAvailability.create!(experience: experience, available_on: Date.today + 21, starts_at: "10:00")
  end
  let(:booking) do
    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2)
  end

  describe "#booking_refused" do
    subject(:mail) { described_class.booking_refused(booking.tap { |b| b.refuse!("Créneau déjà complet") }) }

    it "adresse le mail au client" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "porte la raison du refus et un lien de re-sélection" do
      body = mail.body.encoded
      expect(body).to include("Créneau déjà complet")
      expect(body).to include(stay.activity_selection_token)
    end
  end

  describe "#booking_confirmed" do
    subject(:mail) { described_class.booking_confirmed(booking.tap(&:confirm!)) }

    it "adresse le mail au client et nomme l'activité" do
      expect(mail.to).to eq(["client@example.com"])
      expect(mail.body.encoded).to include("Balade avec les ânes")
    end
  end

  describe "#animateur_notification" do
    subject(:mail) { described_class.animateur_notification(stay) }

    before { booking } # crée une réservation pending

    it "contient un lien de validation (jeton) et un lien de refus pour chaque activité pending" do
      body = mail.body.encoded
      expect(body).to include("/activites/valider/")
      expect(body).to include("/activites/refuser/")
    end
  end
end
