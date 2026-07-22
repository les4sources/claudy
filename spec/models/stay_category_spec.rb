require "rails_helper"

# Catégorie de séjour (Michael 2026-07-21) : clé stable anglaise en base, libellé
# FR à l'affichage. Nullable (historique + funnel optionnel). Une catégorie
# INTERNE (`les4sources`) n'est jamais proposée au public.
RSpec.describe Stay, type: :model do
  let(:customer) { Customer.create!(email: "cat@example.com", customer_type: "individual", first_name: "Ada") }

  def build_stay(category)
    Stay.new(customer: customer, source: "manual", status: "pending",
             arrival_date: Date.today + 10, departure_date: Date.today + 12, category: category)
  end

  describe "validation d'inclusion" do
    it "accepte nil (historique / funnel optionnel)" do
      expect(build_stay(nil)).to be_valid
    end

    Stay::CATEGORIES.each_key do |key|
      it "accepte la clé stable #{key}" do
        expect(build_stay(key)).to be_valid
      end
    end

    it "refuse une valeur hors liste" do
      stay = build_stay("nope")
      expect(stay).not_to be_valid
      expect(stay.errors[:category]).to be_present
    end
  end

  describe ".public_categories" do
    it "expose toutes les catégories SAUF les4sources" do
      expect(Stay.public_categories).not_to have_key("les4sources")
      expect(Stay.public_categories.keys).to match_array(Stay::CATEGORIES.keys - ["les4sources"])
    end

    it "inclut l'amendement (collective, workshop_retreat) et les 12 clés au total" do
      expect(Stay::CATEGORIES.keys).to include("collective", "workshop_retreat")
      expect(Stay::CATEGORIES.size).to eq(12)
      expect(Stay::CATEGORIES["collective"]).to eq("Collectif")
      expect(Stay::CATEGORIES["workshop_retreat"]).to eq("Retraite/Stage")
    end
  end

  describe "#category_label" do
    it "rend le libellé FR" do
      expect(build_stay("wedding").category_label).to eq("Mariage")
    end

    it "rend nil quand aucune catégorie" do
      expect(build_stay(nil).category_label).to be_nil
    end
  end
end
