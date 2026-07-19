require "rails_helper"

# Issue #79 — le funnel PUBLIC persiste désormais camping / van / repas sur leurs
# propres modèles (comme le canal admin). C'est une RE-VENTILATION : le TOTAL du
# séjour et l'ACOMPTE doivent rester STRICTEMENT identiques — seul le Booking
# passe de `lodging_bundle_cents` à `lodging_only_cents`, le reste vivant sur
# CampingBooking / VanBooking / MealOrder.
RSpec.describe Reservations::Builder, "funnel public — persistance à total constant (issue #79)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 } # 2 nuits

  # Draft PUBLIC : camping par-nuit (per_night_resources) + repas sans date.
  let(:draft) do
    Reservations::Draft.new(
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233",
      per_night_resources: { "tente" => ["2", "2"] }, # 2 pers, 2 nuits
      meals: [{ kind: "buffet", people: 3 }]           # public : sans date
    )
  end

  # Valeurs de RÉFÉRENCE issues du devis (source unique, inchangée par la
  # ventilation) = ce que le total et l'acompte valaient AVANT le changement.
  let(:quote) { draft.quote }

  it "persiste camping + repas SANS changer le total ni l'acompte" do
    builder = described_class.new(draft: draft) # admin: false (funnel public)
    expect(builder.run).to be(true)

    stay = builder.stay

    # INVARIANT #79 : total et acompte strictement inchangés (== devis).
    expect(stay.total_amount_cents).to eq(quote.total_excluding_experiences_cents)
    expect(builder.payment.amount_cents).to eq(quote.deposit_cents)

    # Camping / repas désormais PERSISTÉS (avant : noyés dans le Booking).
    camping = stay.stay_items.where(bookable_type: "CampingBooking").first&.bookable
    expect(camping).to be_present
    expect(camping.people).to eq(2)                 # pic simultané, pas 2+2
    expect(camping.price_cents).to eq(quote.camping_cents)
    expect(camping.price_cents).to eq(750 * 2 * 2)  # 7,50 € × 2 pers × 2 nuits

    meal = stay.meal_orders.first
    expect(meal).to be_present
    expect(meal.date).to be_nil                     # repas public sans date (nullable)
    expect(meal.price_cents).to eq(quote.meals_cents)

    # Le Booking d'hébergement porte l'hébergement PUR (extraction sans double-compte).
    booking = stay.stay_items.where(bookable_type: "Booking").first.bookable
    expect(booking.price_cents).to eq(quote.lodging_only_cents)

    # Ventilation exhaustive : la somme des parts redonne exactement le total.
    parts = booking.price_cents + camping.price_cents + stay.meal_orders.sum(:price_cents)
    expect(parts).to eq(stay.total_amount_cents)
  end

  it "ne modifie PAS un séjour public sans camping/van/repas (lodging_only == bundle)" do
    plain = Reservations::Draft.new(
      lodging_id: hulotte.id, arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    )
    builder = described_class.new(draft: plain)
    expect(builder.run).to be(true)

    booking = builder.stay.stay_items.where(bookable_type: "Booking").first.bookable
    # Sans camping/van/repas, lodging_only == lodging_bundle → Booking inchangé.
    expect(booking.price_cents).to eq(plain.quote.lodging_bundle_cents)
    expect(builder.stay.total_amount_cents).to eq(plain.quote.total_excluding_experiences_cents)
    expect(CampingBooking.count).to eq(0)
    expect(MealOrder.count).to eq(0)
  end
end
