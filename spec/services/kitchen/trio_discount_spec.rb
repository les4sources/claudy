require "rails_helper"

# Issue #238 — la remise de formule trio. Elle ramène une journée complète au
# prix annoncé au client (35 €/pers) plutôt qu'à la somme des trois services
# (15 + 7 + 15 = 37 €).
RSpec.describe Kitchen::TrioDiscount do
  let(:stay) do
    Stay.create!(customer: Customer.create!(first_name: "Alice", last_name: "Martin",
                                            email: "alice@example.com"),
                 status: "pending", arrival_date: monday, departure_date: monday + 4)
  end
  let(:monday) { Date.new(2026, 6, 8) }

  def order(moment, kind: nil, people: 10, date: monday, **attrs)
    kind ||= moment == "gouter" ? "gouter" : "repas"
    MealOrder.create!({ stay: stay, kind: kind, moment: moment, date: date,
                        people: people, status: "requested",
                        skip_notifications: true }.merge(attrs))
  end

  def journee(people: 10, date: monday)
    { midi: order("midi", people: people, date: date),
      gouter: order("gouter", people: people, date: date),
      soir: order("soir", people: people, date: date) }
  end

  describe "quand la formule se forme" do
    it "ramène la journée au prix de formule" do
      lignes = journee

      total = lignes.values.sum { |l| l.reload.price_cents }
      expect(total).to eq(35_00 * 10)
    end

    it "laisse midi et soir au tarif plein — la remise est absorbée par le goûter" do
      lignes = journee

      expect(lignes[:midi].reload.price_cents).to eq(15_00 * 10)
      expect(lignes[:soir].reload.price_cents).to eq(15_00 * 10)
      expect(lignes[:gouter].reload.price_cents).to eq(5_00 * 10)
    end

    it "marque les trois lignes « formule trio »" do
      lignes = journee

      expect(lignes.values.map { |l| l.reload.trio_discounted? }).to all(be(true))
    end
  end

  describe "quand elle ne se forme pas" do
    it "laisse chaque service au tarif plein s'il manque le goûter" do
      midi = order("midi")
      soir = order("soir")

      expect(midi.reload.price_cents).to eq(15_00 * 10)
      expect(soir.reload.price_cents).to eq(15_00 * 10)
      expect(midi).not_to be_trio_discounted
    end

    it "ne s'applique pas quand les convives diffèrent d'un service à l'autre" do
      order("midi", people: 10)
      order("gouter", people: 8)
      soir = order("soir", people: 10)

      expect(soir.reload.price_cents).to eq(15_00 * 10)
      expect(soir).not_to be_trio_discounted
    end

    it "n'écrase JAMAIS un prix unitaire forcé à la main" do
      order("midi", unit_price_cents: 2_000)
      order("gouter")
      soir = order("soir")

      expect(soir.reload.price_cents).to eq(15_00 * 10)
      expect(MealOrder.find_by(kind: "gouter").price_cents).to eq(7_00 * 10)
    end

    it "ne se forme pas avec un buffet posé le même jour" do
      order("midi", kind: "buffet_vege")
      order("gouter")
      soir = order("soir")

      expect(soir.reload).not_to be_trio_discounted
    end
  end

  describe "quand une des trois lignes tombe" do
    it "rend le tarif plein aux deux autres quand la cuisine refuse le soir" do
      lignes = journee

      lignes[:soir].refuse!("Steph n'est pas là")

      expect(lignes[:midi].reload.price_cents).to eq(15_00 * 10)
      expect(lignes[:gouter].reload.price_cents).to eq(7_00 * 10)
    end

    it "rend le tarif plein quand le client annule le midi" do
      lignes = journee

      lignes[:midi].update!(status: "cancelled", cancellation_reason: "moins de monde")

      expect(lignes[:gouter].reload.price_cents).to eq(7_00 * 10)
      expect(lignes[:soir].reload.price_cents).to eq(15_00 * 10)
    end

    it "reforme la remise quand la ligne manquante revient" do
      lignes = journee
      lignes[:soir].refuse!("indisponible")
      expect(lignes[:gouter].reload.price_cents).to eq(7_00 * 10)

      lignes[:soir].accept!

      expect(lignes[:gouter].reload.price_cents).to eq(5_00 * 10)
    end

    it "ne reforme pas la formule avec un buffet de remplacement" do
      lignes = journee
      lignes[:soir].refuse!("indisponible")

      order("soir", kind: "buffet_vege")

      expect(lignes[:gouter].reload.price_cents).to eq(7_00 * 10)
    end
  end

  it "rend son tarif plein à la journée qu'une ligne déplacée quitte" do
    lignes = journee
    autre_jour = monday + 1

    lignes[:soir].update!(date: autre_jour)

    expect(lignes[:gouter].reload.price_cents).to eq(7_00 * 10)
  end

  it "laisse `Stay#total` être la simple somme des lignes facturables" do
    journee

    expect(stay.reload.meal_orders.billable.sum(:price_cents)).to eq(35_00 * 10)
  end
end
