require "rails_helper"

# Fusion de séjours (epic #81, Phase 2). Rapatrie toute la composition d'un ou
# plusieurs séjours SOURCES sur la CIBLE (survivant), soft-delete les sources,
# recalcule total / dates (union) / statut de paiement.
RSpec.describe Stays::MergeService, type: :service do
  let(:c_target) { Customer.create!(email: "target@example.com", customer_type: "individual", first_name: "Cible") }
  let(:c_source) { Customer.create!(email: "source@example.com", customer_type: "individual", first_name: "Source") }
  let(:lodging)  { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }

  # Séjour cible : hébergement (300 €) + un paiement encaissé (100 €).
  let(:target) do
    stay = Stay.create!(customer: c_target, source: "manual", status: "confirmed",
                        arrival_date: Date.new(2026, 9, 12), departure_date: Date.new(2026, 9, 15))
    booking = Booking.create!(firstname: "Cible", lodging: lodging, from_date: Date.new(2026, 9, 12),
                              to_date: Date.new(2026, 9, 15), adults: 2, status: "confirmed",
                              booking_type: "lodging", price_cents: 30_000)
    stay.stay_items.create!(bookable: booking)
    Payment.create!(stay: stay, amount_cents: 10_000, status: "paid", payment_method: "card")
    stay.recompute_aggregates!
    stay
  end

  # Séjour source : hébergement (200 €) + repas (80 €) + activité, dates plus tardives.
  let(:porteur)     { Human.create!(name: "Porteur", email: "porteur@example.com") }
  let(:experience)  { Experience.create!(name: "Balade ânes", human: porteur, fixed_price_cents: 4_000, price_cents: 1_500) }
  let(:availability) { ExperienceAvailability.create!(experience: experience, available_on: Date.new(2026, 9, 17), starts_at: "10:00") }
  let(:source) do
    stay = Stay.create!(customer: c_source, source: "manual", status: "confirmed",
                        arrival_date: Date.new(2026, 9, 16), departure_date: Date.new(2026, 9, 18))
    booking = Booking.create!(firstname: "Source", lodging: lodging, from_date: Date.new(2026, 9, 16),
                              to_date: Date.new(2026, 9, 18), adults: 2, status: "confirmed",
                              booking_type: "lodging", price_cents: 20_000)
    stay.stay_items.create!(bookable: booking)
    MealOrder.create!(stay: stay, kind: "buffet", date: Date.new(2026, 9, 17), people: 4, price_cents: 8_000)
    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed")
    Payment.create!(stay: stay, amount_cents: 5_000, status: "paid", payment_method: "card")
    stay.recompute_aggregates!
    stay
  end

  describe "#run (fusion réussie)" do
    subject(:service) { described_class.new(target: target, sources: [source]) }

    it "rapatrie tous les StayItem de la source sur la cible" do
      source_item_ids = source.stay_items.pluck(:id)
      expect { service.run }.to change { target.stay_items.reload.count }.from(1).to(2)
      expect(StayItem.where(id: source_item_ids).pluck(:stay_id).uniq).to eq([target.id])
    end

    it "rapatrie les repas et les activités sur la cible" do
      service.run
      expect(target.meal_orders.reload.count).to eq(1)
      expect(target.experience_bookings.reload.count).to eq(1)
    end

    it "ré-ancre les paiements de la source (payments.stay_id) sur la cible" do
      service.run
      expect(Payment.where(stay_id: source.id)).to be_empty
      expect(target.payments.paid.sum(:amount_cents)).to eq(15_000) # 100 € + 50 €
    end

    it "conserve le client de la cible" do
      expect { service.run }.not_to(change { target.reload.customer_id })
      expect(target.customer_id).to eq(c_target.id)
    end

    it "recalcule le total (union de toute la composition)" do
      service.run
      # 300 (cible) + 200 + 80 (source repas) = 580 €. Activité : 4000 + 2*1500 = 70 €.
      expect(target.reload.total_amount_cents).to eq(30_000 + 20_000 + 8_000 + 7_000)
    end

    it "recalcule les dates en UNION (min arrivée / max départ)" do
      service.run
      expect(target.reload.arrival_date).to eq(Date.new(2026, 9, 12))
      expect(target.departure_date).to eq(Date.new(2026, 9, 18))
    end

    it "recalcule le statut de paiement d'après l'encaissé rapatrié" do
      service.run
      expect(target.reload.payment_status).to eq("partially_paid")
    end

    it "soft-delete la source vidée et expose merged_count" do
      expect(service.run).to be_truthy
      expect(service.merged_count).to eq(1)
      expect(Stay.find_by(id: source.id)).to be_nil                       # hors default scope
      expect(Stay.unscoped.find(source.id).deleted_at).to be_present
    end

    it "trace le changement de séjour des éléments migrés (PaperTrail)" do
      item = source.stay_items.first
      eb = source.experience_bookings.first
      service.run
      expect(item.reload.versions.last.object_changes).to include("stay_id")
      expect(eb.reload.versions.last.object_changes).to include("stay_id")
    end
  end

  describe "fusion de plusieurs sources" do
    let(:c_third) { Customer.create!(email: "third@example.com", customer_type: "individual") }
    let(:third) do
      Stay.create!(customer: c_third, source: "manual", status: "confirmed",
                   arrival_date: Date.new(2026, 9, 20), departure_date: Date.new(2026, 9, 22)).tap do |stay|
        b = Booking.create!(firstname: "Third", lodging: lodging, from_date: Date.new(2026, 9, 20),
                            to_date: Date.new(2026, 9, 22), adults: 1, status: "confirmed",
                            booking_type: "lodging", price_cents: 15_000)
        stay.stay_items.create!(bookable: b)
        stay.recompute_aggregates!
      end
    end

    it "rapatrie les deux sources et les archive" do
      service = described_class.new(target: target, sources: [source, third])
      expect(service.run).to be_truthy
      expect(service.merged_count).to eq(2)
      expect(target.stay_items.reload.count).to eq(3)
      expect(target.departure_date).to eq(Date.new(2026, 9, 22))
    end
  end

  describe "garde-fous" do
    it "refuse une cible nil" do
      service = described_class.new(target: nil, sources: [source])
      expect(service.run).to be(false)
      expect(service.error_message).to be_present
    end

    it "refuse une fusion sans source (moins de deux séjours)" do
      service = described_class.new(target: target, sources: [])
      expect(service.run).to be(false)
      expect(service.error_message).to be_present
    end

    it "refuse que la cible figure parmi les sources" do
      service = described_class.new(target: target, sources: [target])
      expect(service.run).to be(false)
      expect(service.error_message).to be_present
    end
  end
end
