require "rails_helper"

# Cuisine (epic #219, phase 1) — le formulaire du séjour porte désormais le
# moment, les notes et surtout l'IDENTIFIANT de chaque ligne. Ces exemples
# couvrent le chemin réel (params du form → contrôleur → réconciliation).
RSpec.describe "Séjour — section Cuisine du formulaire", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:day) { Date.today + 30 }

  def base_params(overrides = {})
    { stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice-kitchen@example.com", phone: "0470111222" },
        arrival_date: "", departure_date: "",
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: "", status: "pending"
      }.merge(overrides) }
  end

  it "crée une ligne avec son moment et ses notes" do
    expect {
      post stays_path, params: base_params(
        meals: { "0" => { kind: "trio", date: day.iso8601, moment: "midi", people: 10,
                          notes: "une intolérance au gluten" } }
      )
    }.to change(MealOrder, :count).by(1)

    line = MealOrder.order(:created_at).last
    expect(line.kind).to eq("trio")
    expect(line.moment).to eq("midi")
    expect(line.notes).to eq("une intolérance au gluten")
    expect(line.status).to eq("requested")
    expect(line.validation).to eq("pending")
    expect(line.price_cents).to eq(35_000) # 35 €/pers × 10
    expect(line.stay.total_amount_cents).to eq(35_000)
  end

  it "met la ligne à jour en place quand le form renvoie son identifiant" do
    post stays_path, params: base_params(
      meals: { "0" => { kind: "repas", date: day.iso8601, moment: "soir", people: 8 } }
    )
    stay = Stay.order(:created_at).last
    line = stay.meal_orders.sole
    line.update!(validation: "accepted", validated_at: Time.current)

    expect {
      patch stay_path(stay), params: base_params(
        meals: { "0" => { id: line.id, kind: "repas", date: day.iso8601, moment: "soir",
                          people: 14, notes: "table dressée pour 14" } }
      )
    }.not_to change(MealOrder, :count)

    line.reload
    expect(line.people).to eq(14)
    expect(line.notes).to eq("table dressée pour 14")
    expect(line.validation).to eq("pending") # la cuisine doit revalider
    expect(stay.reload.total_amount_cents).to eq(21_000)
  end

  it "annule la ligne que le form ne renvoie plus" do
    post stays_path, params: base_params(
      meals: { "0" => { kind: "buffet_viande", date: day.iso8601, people: 6 } }
    )
    stay = Stay.order(:created_at).last
    line = stay.meal_orders.sole

    patch stay_path(stay), params: base_params(
      meals: { "0" => { kind: "apero", date: day.iso8601, people: 6 } }
    )

    expect(line.reload.status).to eq("cancelled")
    expect(stay.meal_orders.active.map(&:kind)).to eq(["apero"])
  end
end
