require "rails_helper"

# Malau, 2026-08-20 — le client ne recevait plus rien à la confirmation de son
# séjour. Ces exemples verrouillent le déclencheur ET ses garde-fous : c'est
# exactement le silence qui avait disparu sans que personne s'en aperçoive.
RSpec.describe Stays::ConfirmationNotifier do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }

  def build_stay(status: "confirmed", customer: nil, arrival: Date.today + 10, departure: Date.today + 12)
    Stay.create!(customer: customer || self.customer, source: "manual", status: status,
                 arrival_date: arrival, departure_date: departure, total_amount_cents: 30_000)
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  before { deliveries.clear }

  it "envoie l'email et horodate l'envoi sur un séjour confirmé" do
    stay = build_stay

    expect(described_class.call(stay)).to be(true)
    expect(deliveries.size).to eq(1)
    expect(deliveries.last.to).to eq(["guest@example.com"])
    expect(stay.reload.confirmation_email_sent_at).to be_present
  end

  it "n'envoie rien sur un séjour encore en attente" do
    stay = build_stay(status: "pending")

    expect(described_class.call(stay)).to be(false)
    expect(deliveries).to be_empty
  end

  it "n'envoie qu'une fois — un second appel est un non-événement" do
    stay = build_stay

    described_class.call(stay)
    expect(described_class.call(stay)).to be(false)
    expect(deliveries.size).to eq(1)
  end

  # Fourre-tout : l'adresse est une boîte MAISON, pas celle d'un client.
  it "reste muet sur un client fourre-tout" do
    airbnb = Customer.create!(email: Customer::OTA_CATCH_ALL_EMAILS.fetch("airbnb"),
                              customer_type: "organization", organization_name: "Airbnb")
    stay = build_stay(customer: airbnb)

    expect(described_class.call(stay)).to be(false)
    expect(deliveries).to be_empty
  end

  it "reste muet sur un séjour déjà terminé (régularisation d'un vieux dossier)" do
    stay = build_stay(arrival: Date.today - 20, departure: Date.today - 18)

    expect(described_class.call(stay)).to be(false)
    expect(deliveries).to be_empty
  end

  describe "renvoi manuel (force: true)" do
    it "repasse outre l'idempotence" do
      stay = build_stay
      described_class.call(stay)

      expect(described_class.new(stay: stay, force: true).run).to be(true)
      expect(deliveries.size).to eq(2)
    end

    it "repasse outre la borne « séjour terminé »" do
      stay = build_stay(arrival: Date.today - 20, departure: Date.today - 18)

      expect(described_class.new(stay: stay, force: true).run).to be(true)
      expect(deliveries.size).to eq(1)
    end

    it "ne force PAS un envoi absurde : fourre-tout et séjour non confirmé restent bloqués" do
      pending_stay = build_stay(status: "pending")
      expect(described_class.new(stay: pending_stay, force: true).run).to be(false)

      airbnb = Customer.create!(email: Customer::OTA_CATCH_ALL_EMAILS.fetch("bookingdotcom"),
                                customer_type: "organization", organization_name: "Booking.com")
      expect(described_class.new(stay: build_stay(customer: airbnb), force: true).run).to be(false)

      expect(deliveries).to be_empty
    end
  end
end
