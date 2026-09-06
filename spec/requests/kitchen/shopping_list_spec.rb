require "rails_helper"

# Liste de courses imprimable d'une ligne de cuisine (epic #219, phase 6).
RSpec.describe "Cuisine — liste de courses", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen-shopping@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(email: "buffet-shopping@example.com", first_name: "Groupe", last_name: "Buffet") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }
  before { sign_in user }

  def order(**attrs)
    stay.meal_orders.create!({ kind: "buffet_vege", people: 13, notes: "Sans gluten pour deux" }.merge(attrs))
  end

  it "affiche le client, la date, le type, les convives et les quantités calculées" do
    KitchenProduct.create!(name: "Fromage", unit: "g", quantity_per_person: 80, kinds: %w[buffet_vege])
    KitchenProduct.create!(name: "Pain", unit: "piece", quantity_per_person: 0.5, kinds: %w[buffet_vege])
    line = order(date: Date.current + 10)

    get shopping_list_kitchen_order_path(line)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Groupe Buffet")
    expect(response.body).to include("Fromage")
    expect(response.body).to include("1,1 kg")
    expect(response.body).to include("Pain")
    expect(response.body).to include("7 pièces")
    expect(response.body).to include("Sans gluten pour deux")
  end

  it "n'affiche pas la navigation" do
    line = order
    KitchenProduct.create!(name: "Fromage", unit: "g", quantity_per_person: 80, kinds: %w[buffet_vege])

    get shopping_list_kitchen_order_path(line)

    expect(response.body).not_to include('id="subnav-home"')
  end

  it "invite à paramétrer les produits quand aucun n'est configuré pour ce type" do
    line = order

    get shopping_list_kitchen_order_path(line)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(kitchen_products_path)
  end
end
