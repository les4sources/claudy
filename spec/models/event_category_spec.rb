require "rails_helper"

RSpec.describe EventCategory, type: :model do
  it "dérive un slug stable du nom et le dédoublonne, corbeille comprise" do
    first = EventCategory.create!(name: "Ateliers")
    expect(first.slug).to eq("ateliers")
    first.soft_delete!(validate: false)

    second = EventCategory.create!(name: "Ateliers")
    expect(second.slug).to eq("ateliers-2")

    second.update!(name: "Ateliers bois")
    expect(second.slug).to eq("ateliers-2")
  end

  it "convertit un nom de couleur Tailwind en hex et prend le teal de la charte par défaut" do
    expect(EventCategory.create!(name: "A", color: "teal").color).to eq("#0d9488")
    expect(EventCategory.create!(name: "B", color: " #C97B3D ").color).to eq("#c97b3d")
    expect(EventCategory.create!(name: "C").color).to eq("#224246")
    expect(EventCategory.new(name: "D", color: "pas une couleur")).not_to be_valid
  end

  it "n'accepte qu'un pôle de la charte, ou aucun" do
    expect(EventCategory.new(name: "A", pole: "convivialite")).to be_valid
    expect(EventCategory.new(name: "B", pole: "")).to be_valid
    expect(EventCategory.new(name: "C", pole: "finance")).not_to be_valid
    expect(EventCategory.new(name: "D", pole: "vie-collective").pole_label).to eq("Vie collective")
  end
end
