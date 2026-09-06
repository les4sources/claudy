require "rails_helper"

# Paramètres > Cuisine > Produits du buffet (epic #219, phase 6).
RSpec.describe "Cuisine — produits du buffet", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen-products@les4sources.be", password: "password123") }
  before { sign_in user }

  def product(**attrs)
    KitchenProduct.create!({ name: "Fromage", unit: "g", quantity_per_person: 80,
                              kinds: %w[buffet_vege] }.merge(attrs))
  end

  describe "GET /kitchen/products" do
    it "liste les produits triés" do
      product(name: "Pain", position: 2)
      product(name: "Fromage", position: 1)

      get kitchen_products_path

      expect(response).to have_http_status(:ok)
      expect(response.body.index("Fromage")).to be < response.body.index("Pain")
    end
  end

  describe "POST /kitchen/products" do
    it "crée un produit" do
      post kitchen_products_path, params: {
        kitchen_product: { name: "Jambon", unit: "g", quantity_per_person: "60",
                            kinds: ["buffet_viande"], note: "d'ici", position: "1", active: "1" }
      }

      expect(response).to redirect_to(kitchen_products_path)
      product = KitchenProduct.find_by(name: "Jambon")
      expect(product).not_to be_nil
      expect(product.kinds).to eq(["buffet_viande"])
      expect(product.note).to eq("d'ici")
      expect(product.active).to be(true)
    end

    it "refuse un produit invalide et réaffiche le formulaire" do
      post kitchen_products_path, params: {
        kitchen_product: { name: "", unit: "g", quantity_per_person: "60" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(KitchenProduct.count).to eq(0)
    end
  end

  describe "PATCH /kitchen/products/:id" do
    it "met à jour un produit" do
      line = product

      patch kitchen_product_path(line), params: {
        kitchen_product: { name: "Fromage de chèvre", unit: "g", quantity_per_person: "90",
                            kinds: ["buffet_vege", "buffet_viande"], active: "0" }
      }

      expect(response).to redirect_to(kitchen_products_path)
      line.reload
      expect(line.name).to eq("Fromage de chèvre")
      expect(line.kinds).to contain_exactly("buffet_vege", "buffet_viande")
      expect(line.active).to be(false)
    end
  end

  describe "DELETE /kitchen/products/:id" do
    it "supprime réellement le produit" do
      line = product

      delete kitchen_product_path(line)

      expect(response).to redirect_to(kitchen_products_path)
      expect(KitchenProduct.unscoped.exists?(line.id)).to be(false)
    end
  end
end
