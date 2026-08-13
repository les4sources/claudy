require "rails_helper"

# == Schema Information
#
# Table name: lodging_compositions
#
#  id                   :bigint           not null, primary key
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  component_lodging_id :bigint           not null
#  composite_lodging_id :bigint           not null
#
# Indexes
#
#  index_lodging_compositions_on_component_lodging_id  (component_lodging_id)
#  index_lodging_compositions_on_composite_lodging_id  (composite_lodging_id)
#  index_lodging_compositions_unique_pair              (composite_lodging_id,component_lodging_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (component_lodging_id => lodgings.id)
#  fk_rails_...  (composite_lodging_id => lodgings.id)
#
RSpec.describe LodgingComposition, type: :model do
  let(:grand_duc) { Lodging.create!(name: "Le Grand-Duc", price_night_cents: 12_000) }
  let(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }

  it "links a composite lodging to a component lodging" do
    composition = LodgingComposition.new(composite_lodging: grand_duc, component_lodging: hulotte)
    expect(composition).to be_valid
  end

  it "forbids a lodging from composing itself" do
    composition = LodgingComposition.new(composite_lodging: grand_duc, component_lodging: grand_duc)
    expect(composition).not_to be_valid
    expect(composition.errors[:component_lodging_id]).to be_present
  end

  it "forbids the same component twice in one composite" do
    LodgingComposition.create!(composite_lodging: grand_duc, component_lodging: hulotte)
    dup = LodgingComposition.new(composite_lodging: grand_duc, component_lodging: hulotte)
    expect(dup).not_to be_valid
  end
end
