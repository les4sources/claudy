require "rails_helper"

# Round-trip catégorie (Michael 2026-07-21) : `DraftReconstructor` doit
# reconstruire `category` depuis le Stay, sinon l'édition admin — ET surtout
# l'approbation d'une modification client (qui repart d'un draft reconstruit) —
# l'effacerait silencieusement.
RSpec.describe Stays::DraftReconstructor, type: :model do
  let!(:lodging)  { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def build_stay(category)
    draft = Reservations::Draft.new(
      lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
      adults: 2, first_name: "Alice", last_name: "Martin",
      email: "recon-cat@example.com", phone: "0470111222", category: category
    )
    Reservations::Builder.new(draft: draft, admin: true, status: "pending", source: "manual").tap(&:run!).stay
  end

  it "reconstitue la catégorie depuis le Stay" do
    stay = build_stay("team_building")
    draft = described_class.new(stay).to_draft
    expect(draft.category).to eq("team_building")
  end

  it "reconstitue nil quand le séjour n'a pas de catégorie" do
    stay = build_stay(nil)
    draft = described_class.new(stay).to_draft
    expect(draft.category).to be_nil
  end

  it "survit à un update admin sans toucher au select (préservation)" do
    stay = build_stay("retreat")
    draft = Stays::DraftReconstructor.new(stay).to_draft
    Stays::AdminUpdater.new(stay: stay, draft: draft).run!
    expect(stay.reload.category).to eq("retreat")
  end
end
