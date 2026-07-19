require "rails_helper"

# Aperçu dry-run de la fusion (epic #81, Phase 2). Le test le plus important du
# lot est la COHÉRENCE : sur un même jeu de données, l'aperçu annoncé DOIT être
# rigoureusement égal au résultat réel de Stays::MergeService (garantie
# anti-divergence JS/serveur).
RSpec.describe Stays::MergePreview, type: :service do
  let(:c_target) { Customer.create!(email: "target@example.com", customer_type: "individual", first_name: "Cible") }
  let(:c_source) { Customer.create!(email: "source@example.com", customer_type: "individual", first_name: "Source") }
  let(:lodging)  { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }

  def build_stay(customer:, arrival:, departure:, lodging_cents:, paid_cents: nil, pending_cents: nil, meal_cents: nil)
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: arrival, departure_date: departure)
    booking = Booking.create!(firstname: customer.first_name, lodging: lodging, from_date: arrival,
                              to_date: departure, adults: 2, status: "confirmed",
                              booking_type: "lodging", price_cents: lodging_cents)
    stay.stay_items.create!(bookable: booking)
    MealOrder.create!(stay: stay, kind: "buffet", date: arrival, people: 4, price_cents: meal_cents) if meal_cents
    Payment.create!(stay: stay, amount_cents: paid_cents, status: "paid", payment_method: "card") if paid_cents
    Payment.create!(stay: stay, amount_cents: pending_cents, status: "pending", payment_method: "card") if pending_cents
    stay.recompute_aggregates!
    stay.set_payment_status
    stay
  end

  let(:target) { build_stay(customer: c_target, arrival: Date.new(2026, 9, 12), departure: Date.new(2026, 9, 15), lodging_cents: 30_000, paid_cents: 10_000) }
  let(:source) { build_stay(customer: c_source, arrival: Date.new(2026, 9, 16), departure: Date.new(2026, 9, 18), lodging_cents: 20_000, paid_cents: 5_000, meal_cents: 8_000) }

  subject(:preview) { described_class.new(target: target, sources: [source]).call }

  describe "projection" do
    it "conserve le client de la cible" do
      expect(preview.customer_name).to eq(c_target.name)
    end

    it "projette les dates en union" do
      expect(preview.arrival_date).to eq(Date.new(2026, 9, 12))
      expect(preview.departure_date).to eq(Date.new(2026, 9, 18))
    end

    it "projette le nouveau total, le déjà payé et le solde" do
      expect(preview.total_cents).to eq(30_000 + 20_000 + 8_000)
      expect(preview.paid_cents).to eq(15_000)
      expect(preview.balance_cents).to eq(58_000 - 15_000)
    end

    it "liste la composition groupée avec provenance" do
      types = preview.composition.map(&:type)
      expect(types).to include(:lodging, :meal)
      source_line = preview.composition.find { |i| i.origin_stay_id == source.id }
      expect(source_line.from_target).to be(false)
    end

    it "liste les séjours sources archivés" do
      expect(preview.sources.map(&:id)).to eq([source.id])
      expect(preview.sources.first.customer_name).to eq(c_source.name)
    end
  end

  describe "avertissements" do
    it "signale les clients différents" do
      expect(preview.warnings.map(&:kind)).to include(:different_customers)
    end

    it "signale un paiement en attente sur une source" do
      source_with_pending = build_stay(customer: c_source, arrival: Date.new(2026, 10, 1), departure: Date.new(2026, 10, 2), lodging_cents: 10_000, pending_cents: 3_000)
      pv = described_class.new(target: target, sources: [source_with_pending]).call
      expect(pv.warnings.map(&:kind)).to include(:pending_payment)
    end

    it "signale des dates identiques (possible doublon)" do
      twin = build_stay(customer: c_target, arrival: target.arrival_date, departure: target.departure_date, lodging_cents: 12_000)
      pv = described_class.new(target: target, sources: [twin]).call
      expect(pv.warnings.map(&:kind)).to include(:identical_dates)
    end

    it "n'émet aucun avertissement quand tout est net (même client, dates disjointes)" do
      same_client_source = build_stay(customer: c_target, arrival: Date.new(2026, 11, 1), departure: Date.new(2026, 11, 3), lodging_cents: 10_000)
      pv = described_class.new(target: target, sources: [same_client_source]).call
      expect(pv.warnings).to be_empty
    end
  end

  # --- Prix imposé (epic #81, Phase 3) --------------------------------------
  describe "prix imposé" do
    it "projette le total imposé de la cible et signale l'override" do
      target.update!(price_override_cents: 88_000)
      pv = described_class.new(target: target, sources: [source]).call

      expect(pv.total_cents).to eq(88_000) # override cible, pas la somme des items
      expect(pv.warnings.map(&:kind)).to include(:price_override)
    end

    it "signale aussi l'override d'une source (qui sera ignoré à la fusion)" do
      source.update!(price_override_cents: 12_345)
      pv = described_class.new(target: target, sources: [source]).call

      expect(pv.warnings.map(&:kind)).to include(:price_override)
    end

    it "reste rigoureusement cohérent avec la fusion réelle quand la cible porte un override" do
      target.update!(price_override_cents: 88_000)
      snapshot = described_class.new(target: target, sources: [source]).call

      expect(Stays::MergeService.new(target: target, sources: [source]).run).to be_truthy
      target.reload

      aggregate_failures do
        expect(target.total_amount_cents).to eq(snapshot.total_cents)
        expect(target.amount_paid_cents).to eq(snapshot.paid_cents)
        expect(target.amount_due_cents).to eq(snapshot.balance_cents)
      end
    end
  end

  # --- LA garantie anti-divergence ------------------------------------------
  describe "cohérence preview == fusion réelle (garantie anti-divergence)" do
    it "annonce exactement le total / payé / solde / dates que la fusion produit" do
      snapshot = described_class.new(target: target, sources: [source]).call

      service = Stays::MergeService.new(target: target, sources: [source])
      expect(service.run).to be_truthy
      target.reload

      aggregate_failures do
        expect(target.total_amount_cents).to eq(snapshot.total_cents)
        expect(target.amount_paid_cents).to eq(snapshot.paid_cents)
        expect(target.amount_due_cents).to eq(snapshot.balance_cents)
        expect(target.arrival_date).to eq(snapshot.arrival_date)
        expect(target.departure_date).to eq(snapshot.departure_date)
      end
    end

    it "tient aussi avec plusieurs sources et compositions hétérogènes" do
      s2 = build_stay(customer: c_source, arrival: Date.new(2026, 9, 20), departure: Date.new(2026, 9, 25), lodging_cents: 40_000, paid_cents: 12_000, meal_cents: 6_000)
      snapshot = described_class.new(target: target, sources: [source, s2]).call

      expect(Stays::MergeService.new(target: target, sources: [source, s2]).run).to be_truthy
      target.reload

      aggregate_failures do
        expect(target.total_amount_cents).to eq(snapshot.total_cents)
        expect(target.amount_paid_cents).to eq(snapshot.paid_cents)
        expect(target.amount_due_cents).to eq(snapshot.balance_cents)
        expect(target.arrival_date).to eq(snapshot.arrival_date)
        expect(target.departure_date).to eq(snapshot.departure_date)
      end
    end
  end
end
