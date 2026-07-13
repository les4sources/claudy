require "rails_helper"

# Issue #10, Phase 1 — découpage d'un séjour en segments de barre par semaine.
# Semaine de référence : lundi 6 juillet 2026 → dimanche 12 juillet 2026.
RSpec.describe CalendarSegmentsHelper, type: :helper do
  let(:week) { (Date.new(2026, 7, 6)..Date.new(2026, 7, 12)).to_a }
  let(:next_week) { (Date.new(2026, 7, 13)..Date.new(2026, 7, 19)).to_a }

  # Indices dans la semaine : lundi=0 … vendredi=4, samedi=5, dimanche=6.
  # Colonnes 1-indexées : AM = 2d+1, PM = 2d+2.

  describe "#calendar_segment_for" do
    it "vendredi → dimanche : une seule barre, du vendredi PM au dimanche AM" do
      segment = helper.calendar_segment_for(week, Date.new(2026, 7, 10), Date.new(2026, 7, 12))

      expect(segment.start_column).to eq(10) # vendredi PM = 2*4 + 2
      expect(segment.span).to eq(4)          # jusqu'au dimanche AM = colonne 13
      expect(segment.starts_stay).to be(true)
      expect(segment.ends_stay).to be(true)
    end

    it "une nuit (vendredi → samedi) : vendredi PM → samedi AM" do
      segment = helper.calendar_segment_for(week, Date.new(2026, 7, 10), Date.new(2026, 7, 11))

      expect(segment.start_column).to eq(10)
      expect(segment.span).to eq(2)
      expect(segment).to be_starts_stay
      expect(segment).to be_ends_stay
    end

    it "séjour à cheval sur deux semaines : le segment de la 1re semaine est coupé à droite" do
      segment = helper.calendar_segment_for(week, Date.new(2026, 7, 10), Date.new(2026, 7, 15))

      expect(segment.start_column).to eq(10)          # vendredi PM
      expect(segment.span).to eq(5)                   # jusqu'à la fin du dimanche (colonne 14)
      expect(segment.starts_stay).to be(true)
      expect(segment.ends_stay).to be(false)          # ça continue la semaine suivante
    end

    it "séjour à cheval sur deux semaines : le segment de la 2e semaine est coupé à gauche" do
      segment = helper.calendar_segment_for(next_week, Date.new(2026, 7, 10), Date.new(2026, 7, 15))

      expect(segment.start_column).to eq(1)           # lundi AM, bord coupé
      expect(segment.span).to eq(5)                   # jusqu'au mercredi AM (colonne 2*2+1 = 5)
      expect(segment.starts_stay).to be(false)
      expect(segment.ends_stay).to be(true)
    end

    it "semaine entièrement traversée : barre pleine largeur, coupée des deux côtés" do
      segment = helper.calendar_segment_for(week, Date.new(2026, 7, 1), Date.new(2026, 7, 20))

      expect(segment.start_column).to eq(1)
      expect(segment.span).to eq(14)
      expect(segment.starts_stay).to be(false)
      expect(segment.ends_stay).to be(false)
    end

    it "séjour à cheval sur deux mois : la semaine de bord porte bien son segment" do
      # 29 juillet (mer) → 2 août (dim). Semaine du 27 juillet.
      border_week = (Date.new(2026, 7, 27)..Date.new(2026, 8, 2)).to_a
      segment = helper.calendar_segment_for(border_week, Date.new(2026, 7, 29), Date.new(2026, 8, 2))

      expect(segment.start_column).to eq(6)  # mercredi PM = 2*2 + 2
      expect(segment.span).to eq(8)          # jusqu'au dimanche AM = colonne 13
      expect(segment).to be_starts_stay
      expect(segment).to be_ends_stay
    end

    it "ne rend rien quand le séjour ne touche pas la semaine" do
      expect(helper.calendar_segment_for(week, Date.new(2026, 8, 1), Date.new(2026, 8, 3))).to be_nil
      expect(helper.calendar_segment_for(week, Date.new(2026, 6, 1), Date.new(2026, 6, 3))).to be_nil
    end

    it "ne rend rien pour un séjour de 0 nuit (arrivée = départ)" do
      expect(helper.calendar_segment_for(week, Date.new(2026, 7, 10), Date.new(2026, 7, 10))).to be_nil
    end

    it "ne rend rien sans dates" do
      expect(helper.calendar_segment_for(week, nil, Date.new(2026, 7, 10))).to be_nil
      expect(helper.calendar_segment_for(week, Date.new(2026, 7, 10), nil)).to be_nil
    end

    it "arrondit seulement les extrémités réelles du séjour" do
      inside = helper.calendar_segment_for(week, Date.new(2026, 7, 7), Date.new(2026, 7, 9))
      expect(inside.rounded_classes).to eq("rounded-l-full rounded-r-full")

      cut_right = helper.calendar_segment_for(week, Date.new(2026, 7, 7), Date.new(2026, 7, 15))
      expect(cut_right.rounded_classes).to eq("rounded-l-full")

      cut_left = helper.calendar_segment_for(next_week, Date.new(2026, 7, 7), Date.new(2026, 7, 15))
      expect(cut_left.rounded_classes).to eq("rounded-r-full")
    end
  end

  describe "#calendar_segment_style" do
    it "produit un style de grille exploitable" do
      segment = helper.calendar_segment_for(week, Date.new(2026, 7, 10), Date.new(2026, 7, 12))
      expect(helper.calendar_segment_style(segment, 2)).to eq("grid-column: 10 / span 4; grid-row: 2;")
    end
  end

  describe "#calendar_booking_segments" do
    let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

    def booking(from:, to:)
      Booking.create!(firstname: "Test", from_date: from, to_date: to, adults: 1,
                      status: "confirmed", lodging: lodging, price_cents: 0)
    end

    it "ne garde que les bookings qui touchent la semaine" do
      inside = booking(from: Date.new(2026, 7, 10), to: Date.new(2026, 7, 12))
      outside = booking(from: Date.new(2026, 8, 10), to: Date.new(2026, 8, 12))

      result = helper.calendar_booking_segments(week, [inside, outside])

      expect(result.map(&:first)).to eq([inside])
      expect(result.first.last.start_column).to eq(10)
    end

    it "conserve l'ordre reçu (empilement stable d'un rendu à l'autre)" do
      first = booking(from: Date.new(2026, 7, 6), to: Date.new(2026, 7, 8))
      second = booking(from: Date.new(2026, 7, 7), to: Date.new(2026, 7, 9))

      result = helper.calendar_booking_segments(week, [first, second])
      expect(result.map(&:first)).to eq([first, second])
    end
  end
end
