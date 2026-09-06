require "rails_helper"

# Paramètres > Cuisine > Produits du buffet (epic #219, phase 6).
RSpec.describe "Cuisine — produits du buffet", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen-products@les4sources.be", password: "password123") }
  before { sign_in user }

  def product(**attrs)
    KitchenProduct.create!({ name: "Fromage", unit: "g",
                              quantities: { "buffet_vege" => "80" } }.merge(attrs))
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
        kitchen_product: { name: "Jambon", unit: "g", note: "d'ici", position: "1", active: "1",
                            quantities: { buffet_vege: "", buffet_viande: "60", apero: "" } }
      }

      expect(response).to redirect_to(kitchen_products_path)
      product = KitchenProduct.find_by(name: "Jambon")
      expect(product).not_to be_nil
      expect(product.quantities).to eq("buffet_viande" => "60")
      expect(product.note).to eq("d'ici")
      expect(product.active).to be(true)
    end

    it "refuse un produit sans aucune quantité et le dit en clair" do
      post kitchen_products_path, params: {
        kitchen_product: { name: "Olives", unit: "g",
                           quantities: { buffet_vege: "", buffet_viande: "", apero: "" } }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Il faut une quantité pour au moins un type de prestation")
      expect(KitchenProduct.count).to eq(0)
    end

    it "refuse un produit invalide et réaffiche le formulaire" do
      post kitchen_products_path, params: {
        kitchen_product: { name: "", unit: "g", quantities: { buffet_vege: "60" } }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(KitchenProduct.count).to eq(0)
    end
  end

  describe "PATCH /kitchen/products/:id" do
    it "met à jour un produit" do
      line = product

      patch kitchen_product_path(line), params: {
        kitchen_product: { name: "Fromage de chèvre", unit: "g", active: "0",
                            quantities: { buffet_vege: "90", buffet_viande: "50", apero: "" } }
      }

      expect(response).to redirect_to(kitchen_products_path)
      line.reload
      expect(line.name).to eq("Fromage de chèvre")
      expect(line.quantities).to eq("buffet_vege" => "90", "buffet_viande" => "50")
      expect(line.active).to be(false)
    end
  end

  describe "PATCH — retrait d'un type" do
    it "retire le type dont on vide la quantité" do
      line = product(quantities: { "buffet_vege" => "80", "buffet_viande" => "50" })

      patch kitchen_product_path(line), params: {
        kitchen_product: { name: "Fromage", unit: "g", active: "1",
                           quantities: { buffet_vege: "80", buffet_viande: "", apero: "" } }
      }

      expect(line.reload.kinds).to eq(["buffet_vege"])
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
