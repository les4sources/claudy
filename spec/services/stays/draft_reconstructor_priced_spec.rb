require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Michael, 2026-10-12 : un devis recalculé depuis un séjour enregistré doit
# retrouver celui du funnel. Deux écarts constatés : les salles réservées par
# la grille (tarif week-end, forfaits) se recalculaient à l'unité au tarif
# semaine, et le supplément chien disparaissait — du devis comme du prix, au
# premier réenregistrement.
RSpec.describe Stays::DraftReconstructor do
  include FinanceBuilders

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end
  let!(:petite_salle) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

  let(:saturday) { (Date.today + 50).next_occurring(:saturday) }
  let(:funnel_draft) do
    Reservations::Draft.new(
      lodging_id: hulotte.id,
      arrival_date: (saturday - 1).iso8601, departure_date: (saturday + 1).iso8601,
      dogs_count: 1, adults: 2,
      first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470000000",
      space_slots: { "petite_salle" => ["", "journee_et_soiree", "journee"] }
    )
  end
  let(:builder) do
    builder = Reservations::Builder.new(draft: funnel_draft)
    raise builder.error_message(default: "Builder KO") unless builder.run

    builder
  end
  let(:stay) { builder.stay.reload }

  it "garde le nombre de chiens sur le séjour" do
    expect(stay.dogs_count).to eq(1)
    expect(described_class.call(stay).dogs_count).to eq(1)
  end

  describe ".priced" do
    it "retrouve le devis du funnel, ligne par ligne" do
      expect(described_class.priced(stay).quote.lines.map(&:to_h))
        .to eq(builder.quote.lines.map(&:to_h))
    end

    it "passe les salles en grille et laisse `call` en lignes datées" do
      expect(described_class.priced(stay).halls).to be_empty
      expect(described_class.priced(stay).space_slots["petite_salle"]).to eq(["", "journee_et_soiree", "journee"])
      expect(described_class.call(stay).halls).not_to be_empty
    end
  end

  it "un réenregistrement admin sans changement garde le prix, supplément chien compris" do
    total = stay.total_amount_cents
    draft = described_class.call(stay)
    Stays::SpaceGridPrefill.apply!(draft, (stay.arrival_date..stay.departure_date).to_a)

    Stays::AdminUpdater.new(stay: stay, draft: draft).run!

    expect(stay.reload.total_amount_cents).to eq(total)
    expect(stay.dogs_count).to eq(1)
  end

  it "ventile sur les mêmes parts que le devis du funnel" do
    salles      = build_general_account(code: "700100", name: "Salles", klass: 7, nature: "revenue")
    hebergement = build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue")
    RevenueMapping.create!(category: "spaces", general_account: salles)
    RevenueMapping.create!(category: "lodging", general_account: hebergement)

    lines = Finance::VentilateStay.new(stay: stay, amount_cents: builder.quote.total_cents).run!
    by_category = lines.to_h { |line| [line.category, line.amount_cents] }

    expect(by_category).to eq("spaces" => builder.quote.spaces_cents, "lodging" => builder.quote.lodging_only_cents)
  end
end
