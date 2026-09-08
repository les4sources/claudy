require "rails_helper"

# Issue #238 — le goûter devient un service facturable à part, et `trio` quitte
# les types proposables.
RSpec.describe "Le goûter et la fin du type trio" do
  after { Pricing::Rates.reset! }

  it "existe comme type, rattaché à la famille « repas »" do
    expect(MealOrder::KINDS).to include("gouter")
    expect(MealOrder::KIND_FAMILIES["gouter"]).to eq("repas")
    expect(MealOrder.label_for("gouter")).to eq("Goûter")
  end

  it "vaut 7 € par personne au barème" do
    expect(Pricing::Catalog.meal_per_person_cents("gouter")).to eq(700)
  end

  it "est semé sous la clé `meal.gouter.per_person`, éditable dans Paramètres > Tarifs" do
    Rates::SeedFromCatalog.new.run

    expect(Rate.find_by(key: "meal.gouter.per_person").amount_cents).to eq(700)
  end

  it "suit le tarif édité en base" do
    Rate.create!(key: "meal.gouter.per_person", amount_cents: 850, label: "Goûter")
    Pricing::Rates.reset!

    expect(Pricing::Catalog.meal_per_person_cents("gouter")).to eq(850)
  end

  describe "le type `trio`" do
    it "n'est plus proposable à la saisie" do
      expect(Kitchen::Config.enabled_kinds).not_to include("trio")
      expect(Kitchen::Config.enabled_kinds).to include("repas", "buffet_vege", "apero")
    end

    it "ne se propose pas non plus par le goûter — il se coche dans la grille" do
      expect(Kitchen::Config.enabled_kinds).not_to include("gouter")
    end

    it "garde son tarif : c'est celui de la formule" do
      expect(Pricing::Catalog.meal_per_person_cents("trio")).to eq(3_500)
    end

    it "reste accepté par le modèle — d'anciennes lignes pourraient exister" do
      expect(MealOrder::KINDS).to include("trio")
    end
  end

  describe "la migration de garde" do
    # Les migrations ne sont pas autochargées : on charge celle-ci à la main
    # pour vérifier qu'elle refuse bien de passer sur des données incohérentes.
    before do
      path = Rails.root.glob("db/migrate/*_add_gouter_meal_kind.rb").first
      require path.to_s
    end

    it "échoue bruyamment s'il reste une ligne de type `trio`" do
      stay = Stay.create!(customer: Customer.create!(first_name: "Alice", last_name: "Martin",
                                                     email: "alice@example.com"),
                          status: "pending")
      MealOrder.create!(stay: stay, kind: "trio", people: 4, status: "requested",
                        skip_notifications: true)

      migration = AddGouterMealKind.new

      expect { migration.up }.to raise_error(/type `trio`/)
    end

    it "passe sans bruit quand il n'en reste aucune" do
      expect { AddGouterMealKind.new.up }.not_to raise_error
    end
  end
end
