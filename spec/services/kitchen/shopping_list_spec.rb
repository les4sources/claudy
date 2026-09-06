require "rails_helper"

# Calcul de la liste de courses d'une ligne de cuisine (epic #219, phase 6).
# L'arrondi est TOUJOURS vers le haut — mieux vaut acheter un peu trop que pas
# assez — à l'unité pour les pièces, au gramme ou au millilitre sinon, et de
# nouveau vers le haut pour l'affichage condensé en kilos ou en litres.
RSpec.describe Kitchen::ShoppingList do
  let(:customer) { Customer.create!(email: "buffet@example.com", first_name: "Buffet", last_name: "Test") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }

  def order(**attrs)
    stay.meal_orders.create!({ kind: "buffet_vege", people: 13 }.merge(attrs))
  end

  def product(**attrs)
    KitchenProduct.create!({ name: "Fromage", unit: "g", active: true,
                              quantities: { "buffet_vege" => "80", "buffet_viande" => "80" } }.merge(attrs))
  end

  describe "#lines" do
    it "arrondit vers le haut au gramme et affiche en kilos au-delà de 1000 g" do
      product(name: "Fromage", unit: "g", quantities: { "buffet_vege" => "80" })

      list = described_class.new(order(people: 13))

      expect(list.lines.size).to eq(1)
      line = list.lines.first
      expect(line.product.name).to eq("Fromage")
      expect(line.quantity).to eq(1040)
      expect(line.display).to eq("1,1 kg")
    end

    it "arrondit vers le haut à la pièce" do
      product(name: "Pain", unit: "piece", quantities: { "buffet_vege" => "0.5" })

      line = described_class.new(order(people: 13)).lines.first

      expect(line.quantity).to eq(7)
      expect(line.display).to eq("7 pièces")
    end

    it "arrondit vers le haut au millilitre et affiche en litres au-delà de 1000 ml" do
      product(name: "Jus", unit: "ml", quantities: { "apero" => "120" })

      line = described_class.new(order(kind: "apero", people: 10)).lines.first

      expect(line.quantity).to eq(1200)
      expect(line.display).to eq("1,2 l")
    end

    it "affiche en dessous du seuil dans l'unité brute" do
      product(name: "Beurre", unit: "g", quantities: { "buffet_vege" => "10" })

      line = described_class.new(order(people: 13)).lines.first

      expect(line.quantity).to eq(130)
      expect(line.display).to eq("130 g")
    end

    it "ignore un produit inactif" do
      product(active: false, quantities: { "buffet_vege" => "80" })

      expect(described_class.new(order).lines).to be_empty
    end

    it "ignore un produit d'un autre type" do
      product(quantities: { "buffet_viande" => "80" })

      expect(described_class.new(order(kind: "buffet_vege")).lines).to be_empty
    end

    it "applique la quantité du type demandé, pas celle de l'autre buffet" do
      product(name: "Fromages", unit: "g",
              quantities: { "buffet_vege" => "80", "buffet_viande" => "50" })

      vege   = described_class.new(order(kind: "buffet_vege", people: 10)).lines.first
      viande = described_class.new(order(kind: "buffet_viande", people: 10)).lines.first

      expect(vege.quantity).to eq(800)
      expect(viande.quantity).to eq(500)
    end

    it "ne propose pas le jambon sur un buffet végé" do
      product(name: "Fromage", unit: "g", quantities: { "buffet_vege" => "80", "buffet_viande" => "80" })
      product(name: "Jambon", unit: "g", quantities: { "buffet_viande" => "60" })
      product(name: "Pain", unit: "piece", quantities: { "buffet_vege" => "0.5", "buffet_viande" => "0.5", "apero" => "0.5" })

      names = described_class.new(order(kind: "buffet_vege", people: 13)).lines.map { |l| l.product.name }

      expect(names).to contain_exactly("Fromage", "Pain")
    end
  end

  describe "#empty?" do
    it "est vrai quand aucun produit ne correspond au type" do
      expect(described_class.new(order).empty?).to be(true)
    end

    it "est faux dès qu'un produit correspond" do
      product(quantities: { "buffet_vege" => "80" })

      expect(described_class.new(order).empty?).to be(false)
    end
  end
end
