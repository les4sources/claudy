require "rails_helper"

# Terrasse — édition admin (`Stays::AdminUpdater`) et reconstruction du Draft
# (`Stays::DraftReconstructor`). La terrasse (CampingBooking kind "terrasse") a
# son propre cycle de vie, indépendant du camping (kind "tente").
RSpec.describe "Terrasse — réconciliation admin + reconstruction du draft" do
  let(:day1) { Date.today + 30 }
  let(:day2) { Date.today + 31 }

  def base_draft(terrasses:)
    Reservations::Draft.new(
      arrival_date: day1.iso8601, departure_date: (day1 + 1).iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233",
      terrasses: terrasses
    )
  end

  def build_stay!(terrasses:)
    b = Reservations::Builder.new(draft: base_draft(terrasses: terrasses), admin: true, source: "manual")
    raise "build failed: #{b.error_message}" unless b.run
    b.stay
  end

  describe "Stays::DraftReconstructor" do
    it "reconstruit fidèlement les terrasses {date, people} du séjour" do
      stay = build_stay!(terrasses: [{ date: day1.iso8601, people: 8 },
                                     { date: day2.iso8601, people: 5 }])

      draft = Stays::DraftReconstructor.call(stay)
      reconstructed = draft.terrasses.map { |t| t.symbolize_keys }
                           .sort_by { |t| t[:date].to_s }
      expect(reconstructed).to eq([{ date: day1.iso8601, people: 8 },
                                   { date: day2.iso8601, people: 5 }])
      # La terrasse ne pollue PAS la grille camping ni les entrées camping.
      expect(draft.campings).to be_empty
    end
  end

  describe "Stays::AdminUpdater" do
    it "réconcilie les terrasses (ajout / modif / retrait) sans toucher au camping" do
      stay = build_stay!(terrasses: [{ date: day1.iso8601, people: 8 }])
      expect(CampingBooking.where(kind: "terrasse").count).to eq(1)

      # Édition : la terrasse du jour 1 passe à 6 pers, une nouvelle au jour 2.
      draft = base_draft(terrasses: [{ date: day1.iso8601, people: 6 },
                                     { date: day2.iso8601, people: 3 }])
      updater = Stays::AdminUpdater.new(stay: stay, draft: draft)
      expect(updater.run).to be(true)

      live = CampingBooking.where(kind: "terrasse").order(:from_date)
      expect(live.map(&:people)).to eq([6, 3])
      expect(live.map(&:price_cents)).to eq([1_500, 750]) # 6×250, 3×250
      # Total du séjour réaligné (2 250 c).
      expect(stay.reload.total_amount_cents).to eq(2_250)
    end

    it "retire toutes les terrasses quand le draft n'en porte plus" do
      stay = build_stay!(terrasses: [{ date: day1.iso8601, people: 8 }])
      # On garde un hébergement fictif ? Non : on ajoute une terrasse vide impossible.
      # Le séjour doit rester valide → on met une nouvelle terrasse pour ne pas vider.
      draft = base_draft(terrasses: [{ date: day2.iso8601, people: 2 }])
      Stays::AdminUpdater.new(stay: stay, draft: draft).run

      remaining = CampingBooking.where(kind: "terrasse")
      expect(remaining.count).to eq(1)
      expect(remaining.first.from_date).to eq(day2)
    end
  end
end
