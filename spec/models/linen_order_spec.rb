require "rails_helper"

# Epic #260, phase 2 — la ligne de draps : par lit, jamais par nuit.
# == Schema Information
#
# Table name: linen_orders
#
#  id               :bigint           not null, primary key
#  deleted_at       :datetime
#  kind             :string           not null
#  price_cents      :integer
#  quantity         :integer          default(1), not null
#  unit_price_cents :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  stay_id          :bigint           not null
#
# Indexes
#
#  index_linen_orders_on_deleted_at                 (deleted_at)
#  index_linen_orders_on_stay_and_kind_unique_live  (stay_id,kind) UNIQUE WHERE (deleted_at IS NULL)
#  index_linen_orders_on_stay_id                    (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (stay_id => stays.id)
#
RSpec.describe LinenOrder do
  let(:customer) { Customer.create!(first_name: "Camille", last_name: "Martin", email: "camille@example.com") }
  let(:stay) do
    Stay.create!(customer: customer, status: "pending",
                 arrival_date: Date.today, departure_date: Date.today + 2)
  end

  it "calcule son total depuis le barème quand aucun prix n'est posé" do
    order = stay.linen_orders.create!(kind: "double_bed", quantity: 3)

    expect(order.price_cents).to eq(6_000)
  end

  it "respecte un total posé explicitement (ventilation du devis)" do
    order = stay.linen_orders.create!(kind: "single_bed", quantity: 2, price_cents: 1_900)

    expect(order.price_cents).to eq(1_900)
  end

  it "refuse un type inconnu" do
    expect(stay.linen_orders.new(kind: "sofa", quantity: 1)).not_to be_valid
  end

  it "refuse une quantité nulle ou négative" do
    expect(stay.linen_orders.new(kind: "single_bed", quantity: 0)).not_to be_valid
    expect(stay.linen_orders.new(kind: "single_bed", quantity: -2)).not_to be_valid
  end

  it "compte dans le total du séjour recalculé" do
    stay.linen_orders.create!(kind: "single_bed", quantity: 2)
    stay.recompute_aggregates!

    expect(stay.reload.total_amount_cents).to eq(2_000)
  end

  it "sort du total une fois soft-deleted" do
    order = stay.linen_orders.create!(kind: "single_bed", quantity: 2)
    order.soft_delete!
    stay.linen_orders.reset
    stay.recompute_aggregates!

    expect(stay.reload.total_amount_cents).to eq(0)
  end
end
