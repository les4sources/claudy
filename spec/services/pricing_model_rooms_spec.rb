require "rails_helper"

# Epic #81, Phase 5 — devis en mode « chambres seules ». Le barème B2C
# (`LODGING_RATES`) est un forfait par gîte ENTIER : il n'existe pas de tarif
# par chambre. En mode "rooms", PricingModel ne facture donc AUCUN forfait
# d'hébergement — le total du séjour vient du Prix total imposé (override).
RSpec.describe PricingModel, "mode chambres seules (epic #81, Phase 5)" do
  let!(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: "2026-08-01",
      departure_date: "2026-08-03"
    }.merge(overrides))
  end

  it "facture le forfait gîte entier en mode lodging (comportement historique)" do
    quote = PricingModel.quote(draft(booking_type: "lodging"))
    # La Hulotte = 485 € + 260 € = 745 € sur 2 nuits.
    expect(quote.total_cents).to eq(74_500)
  end

  it "ne facture AUCUN forfait d'hébergement en mode rooms" do
    quote = PricingModel.quote(draft(booking_type: "rooms", room_ids: [1]))
    expect(quote.total_cents).to eq(0)
    expect(quote.breakdown).to be_empty
  end

  it "continue de facturer les autres composantes en mode rooms (ex. chien)" do
    quote = PricingModel.quote(draft(booking_type: "rooms", room_ids: [1], dogs_count: 1))
    # Pas de forfait gîte, mais le supplément chien (50 €) reste dû.
    expect(quote.total_cents).to eq(5_000)
  end
end
