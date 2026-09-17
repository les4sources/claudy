require "rails_helper"

# Epic #260, phase 2 — deux alignements sur la page tarifs du site :
#   · le hamac vaut 10 €/nuit, simple comme double (décision 7) ;
#   · la brouette de bûches est incluse à La Chevêche et au Grand-Duc, pas à
#     La Hulotte qui n'a pas de poêle (décision 6).
RSpec.describe "Hamacs et bûches conformes au site (epic #260, phase 2)" do
  describe "tarif du hamac" do
    it "vaut 10 € la nuit pour les deux types, sans tarif en base ni RentalItem" do
      expect(Pricing::Catalog.hamac_rate("simple")).to eq(1_000)
      expect(Pricing::Catalog.hamac_rate("double")).to eq(1_000)
    end

    it "facture 1 hamac double sur 3 nuits à 30 €" do
      arrival = (Date.today + 30).next_occurring(:monday)
      quote = Reservations::Draft.new(
        arrival_date: arrival.iso8601, departure_date: (arrival + 3).iso8601,
        per_night_resources: { "hamac_double" => %w[1 1 1] }
      ).quote

      expect(quote.hamac_cents).to eq(3_000)
    end

    it "facture 1 hamac simple sur 3 nuits au même prix qu'un double" do
      arrival = (Date.today + 30).next_occurring(:monday)
      simple = Reservations::Draft.new(
        arrival_date: arrival.iso8601, departure_date: (arrival + 3).iso8601,
        per_night_resources: { "hamac_simple" => %w[1 1 1] }
      ).quote

      expect(simple.hamac_cents).to eq(3_000)
    end

    it "laisse le RentalItem primer quand il porte un prix différent" do
      RentalItem.create!(name: "Hamac simple", stock: 2, price_cents: 1_400)

      expect(Pricing::Catalog.hamac_rate("simple")).to eq(1_400)
    end
  end

  describe "brouette de bûches incluse" do
    it "l'inclut à La Chevêche et au Grand-Duc" do
      expect(Pricing::Catalog.firewood_included?("La Chevêche")).to be(true)
      expect(Pricing::Catalog.firewood_included?("Le Grand-Duc")).to be(true)
    end

    it "ne l'annonce pas à La Hulotte, qui n'a pas de poêle" do
      expect(Pricing::Catalog.firewood_included?("La Hulotte")).to be(false)
    end

    it "n'est JAMAIS une ligne de prix du devis" do
      cheveche = Lodging.create!(name: "La Chevêche", price_night_cents: 27_500)
      arrival  = (Date.today + 30).next_occurring(:monday)

      quote = Reservations::Draft.new(
        lodging_id: cheveche.id,
        arrival_date: arrival.iso8601, departure_date: (arrival + 2).iso8601
      ).quote

      expect(quote.lines.map(&:label).join(" ")).not_to include("bûches")
    end
  end
end
