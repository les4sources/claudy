require "rails_helper"

# Refonte séjour (2026-07-22) : les heures d'arrivée/départ REMONTENT AU SÉJOUR
# (`stays.arrival_time` / `departure_time`, type string) au lieu de vivre sur le
# `SpaceBooking`. Round-trip complet : le Builder les écrit à la création, l'
# AdminUpdater les met à jour, le DraftReconstructor les relit — avec BACKFILL
# depuis le SpaceBooking pour les séjours antérieurs à la migration.
RSpec.describe "Séjour — heures d'arrivée/départ portées par le Stay", type: :model do
  let!(:lodging)      { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 4) }
  let(:arrival)       { Date.today + 30 }
  let(:departure)     { Date.today + 32 }

  def build_draft(overrides = {})
    Reservations::Draft.new({
      lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
      adults: 2, first_name: "Alice", last_name: "Martin",
      email: "stay-times@example.com", phone: "0470111222"
    }.merge(overrides))
  end

  def create_stay(overrides = {})
    Reservations::Builder.new(draft: build_draft(overrides), admin: true, status: "pending", source: "manual")
                         .tap(&:run!).stay
  end

  describe "Reservations::Builder (création)" do
    it "écrit les heures sur le Stay depuis le draft" do
      stay = create_stay(arrival_time: "14:00", departure_time: "11:00")
      expect(stay.arrival_time).to eq("14:00")
      expect(stay.departure_time).to eq("11:00")
    end

    it "laisse les heures à nil quand le draft n'en porte pas" do
      stay = create_stay
      expect(stay.arrival_time).to be_nil
      expect(stay.departure_time).to be_nil
    end
  end

  describe "Stays::AdminUpdater (édition)" do
    it "met à jour les heures du séjour" do
      stay  = create_stay(arrival_time: "14:00", departure_time: "11:00")
      draft = build_draft(arrival_time: "15:30", departure_time: "10:00")
      Stays::AdminUpdater.new(stay: stay, draft: draft).run!
      expect(stay.reload.arrival_time).to eq("15:30")
      expect(stay.reload.departure_time).to eq("10:00")
    end

    it "vide les heures quand le draft ne les porte plus" do
      stay  = create_stay(arrival_time: "14:00", departure_time: "11:00")
      Stays::AdminUpdater.new(stay: stay, draft: build_draft).run!
      expect(stay.reload.arrival_time).to be_nil
      expect(stay.reload.departure_time).to be_nil
    end
  end

  describe "Stays::DraftReconstructor (relecture)" do
    it "relit les heures depuis le Stay" do
      stay  = create_stay(arrival_time: "14:00", departure_time: "11:00")
      draft = Stays::DraftReconstructor.new(stay).to_draft
      expect(draft.arrival_time).to eq("14:00")
      expect(draft.departure_time).to eq("11:00")
    end

    it "BACKFILL : Stay sans heures + SpaceBooking avec heures → heures du SpaceBooking" do
      # Séjour espace facturé, puis on simule l'état pré-migration : heures
      # portées par le SpaceBooking, absentes du Stay.
      draft = build_draft(halls: [{ kind: "grande_salle", date: arrival.iso8601, period: "journee" }])
      stay  = Reservations::Builder.new(draft: draft, admin: true, status: "pending", source: "manual").tap(&:run!).stay
      stay.update_columns(arrival_time: nil, departure_time: nil)
      sb = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
      sb.update_columns(arrival_time: "16:00", departure_time: "09:30")

      reconstructed = Stays::DraftReconstructor.new(stay.reload).to_draft
      expect(reconstructed.arrival_time).to eq("16:00")
      expect(reconstructed.departure_time).to eq("09:30")
    end

    it "les heures du Stay priment sur celles du SpaceBooking" do
      draft = build_draft(
        arrival_time: "14:00", departure_time: "11:00",
        halls: [{ kind: "grande_salle", date: arrival.iso8601, period: "journee" }]
      )
      stay = Reservations::Builder.new(draft: draft, admin: true, status: "pending", source: "manual").tap(&:run!).stay
      sb   = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
      sb.update_columns(arrival_time: "16:00", departure_time: "09:30")

      reconstructed = Stays::DraftReconstructor.new(stay.reload).to_draft
      expect(reconstructed.arrival_time).to eq("14:00")
      expect(reconstructed.departure_time).to eq("11:00")
    end
  end
end
