require "rails_helper"

# Epic #260, phase 3 — « la totale » dans le devis.
#
# Quand la composition est celle du forfait, les lignes gîte ET salles
# disparaissent au profit d'une seule ligne. Sinon, prix à l'unité comme avant.
RSpec.describe PricingModel, "la totale (epic #260, phase 3)" do
  let!(:grand_duc) { Lodging.find_by(name: "Le Grand-Duc") || Lodging.create!(name: "Le Grand-Duc", price_night_cents: 75_000) }
  let!(:hulotte)   { Lodging.find_by(name: "La Hulotte") || Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  let(:lundi_5_octobre) { Date.new(2026, 10, 5) }

  def draft(nights_count:, arrival: lundi_5_octobre, lodging_ids: nil, spaces: Pricing::FullPackage::REQUIRED_SPACES, holes: {})
    departure = arrival + nights_count
    days = (arrival..departure).to_a
    slots = spaces.to_h do |space|
      periods = days.map { "journee" }
      Array(holes[space]).each { |index| periods[index] = nil }
      [space, periods]
    end

    OpenStruct.new(
      lodging: grand_duc, nights: nights_count,
      arrival_date: arrival, departure_date: departure,
      lodging_night_ids: lodging_ids || Array.new(nights_count) { grand_duc.id },
      space_slots: slots,
      campings: [], vans: [], halls: [], meals: [], pizza_parties: []
    )
  end

  describe "quand elle s'applique" do
    it "remplace gîte et salles par UNE ligne, au montant figé par l'epic" do
      quote = described_class.quote(draft(nights_count: 3))

      expect(quote.total_cents).to eq(272_700)
      expect(quote.lines.size).to eq(2)

      totale = quote.lines.first
      expect(totale.label).to include("La totale — Le Grand-Duc + les 2 salles + cuisine pro")
      expect(totale.label).to include("3 nuits", "haute saison", "−10 %")
      expect(totale.amount_cents).to eq(272_700)
    end

    it "garde une ligne d'espaces à 0 €, pour qu'on ne les croie pas oubliés" do
      quote = described_class.quote(draft(nights_count: 3))

      espaces = quote.lines.find { |l| l.category == :space }
      expect(espaces.amount_cents).to eq(0)
      expect(espaces.label).to include("compris dans la totale")
    end

    it "ventile tout sur l'hébergement, rien sur les espaces" do
      quote = described_class.quote(draft(nights_count: 3))

      expect(quote.lodging_only_cents).to eq(272_700)
      expect(quote.spaces_cents).to eq(0)
      expect(quote.lodging_only_cents + quote.spaces_cents).to eq(quote.total_excluding_experiences_cents)
    end

    it "assoit l'acompte sur la totale" do
      quote = described_class.quote(draft(nights_count: 3))
      expect(quote.deposit_cents).to eq(136_350)
    end
  end

  describe "quand elle ne s'applique pas" do
    it "revient au prix à l'unité si une salle manque un seul jour" do
      quote = described_class.quote(draft(nights_count: 3, holes: { "cuisine_pro" => [2] }))

      expect(quote.lines.map(&:label).join).not_to include("La totale")
      expect(quote.spaces_cents).to be_positive
      expect(quote.lodging_only_cents).to be_positive
    end

    it "revient au prix à l'unité si la cuisine pro n'est pas prise du tout" do
      quote = described_class.quote(draft(nights_count: 3, spaces: %w[grande_salle petite_salle]))
      expect(quote.lines.map(&:label).join).not_to include("La totale")
    end

    it "revient au prix à l'unité si une nuit se fait dans un autre gîte" do
      ids = [grand_duc.id, hulotte.id, grand_duc.id]
      quote = described_class.quote(draft(nights_count: 3, lodging_ids: ids))
      expect(quote.lines.map(&:label).join).not_to include("La totale")
    end

    it "revient au prix à l'unité sur une seule nuit" do
      quote = described_class.quote(draft(nights_count: 1))
      expect(quote.lines.map(&:label).join).not_to include("La totale")
    end
  end

  describe "les autres lignes restent" do
    it "laisse les repas et le chien à côté de la totale" do
      base = draft(nights_count: 3)
      base.meals = [{ kind: "repas", people: 4 }]
      base.dogs_count = 1

      quote = described_class.quote(base)

      labels = quote.lines.map(&:label).join(" | ")
      expect(labels).to include("La totale")
      expect(quote.meals_cents).to be_positive
      expect(quote.total_cents).to be > 272_700
    end
  end
end
