require "rails_helper"

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
