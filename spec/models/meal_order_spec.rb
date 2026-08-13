require "rails_helper"

# Epic #66, Phase 3 — MealOrder : commande de repas datée rattachée directement
# au séjour (has_many), hors calendrier. `date` nullable (repas funnel sans date).
# == Schema Information
#
# Table name: meal_orders
#
#  id          :bigint           not null, primary key
#  date        :date
#  deleted_at  :datetime
#  kind        :string
#  people      :integer          default(1), not null
#  price_cents :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  stay_id     :bigint           not null
#
# Indexes
#
#  index_meal_orders_on_deleted_at  (deleted_at)
#  index_meal_orders_on_stay_id     (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (stay_id => stays.id)
#
RSpec.describe MealOrder do
  let(:customer) { Customer.create!(email: "meal@example.com", first_name: "Meal", last_name: "Test") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }

  it "exige un type et un nombre de convives positif" do
    expect(described_class.new(stay: stay, kind: nil, people: 2)).not_to be_valid
    expect(described_class.new(stay: stay, kind: "buffet", people: 0)).not_to be_valid
  end

  it "tolère une date nulle (repas funnel sans date)" do
    order = described_class.create!(stay: stay, kind: "buffet", people: 3, date: nil, price_cents: 3_600)
    expect(order).to be_persisted
    expect(order.date).to be_nil
  end

  it "expose un libellé lisible" do
    expect(described_class.new(kind: "repas_vege_midi").label).to eq("Repas végé (midi)")
    expect(described_class.new(kind: "inconnu").label).to eq("Inconnu")
  end

  it "est exclue du séjour après soft-delete (default_scope)" do
    order = described_class.create!(stay: stay, kind: "buffet", people: 2, price_cents: 2_400)
    expect(stay.meal_orders).to include(order)
    order.soft_delete!(validate: false)
    expect(stay.meal_orders.reload).to be_empty
  end
end
