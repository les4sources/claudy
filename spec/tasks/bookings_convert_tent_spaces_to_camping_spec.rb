require "rails_helper"
require "rake"

RSpec.describe "bookings:convert_tent_spaces_to_camping", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("bookings:convert_tent_spaces_to_camping")
  end

  # Exécute la tâche et renvoie sa sortie (rapport ventilé), silençée du flux de
  # test. `apply: true` pose APPLY=1 le temps de l'invocation.
  def run_task(apply: false)
    task = Rake::Task["bookings:convert_tent_spaces_to_camping"]
    task.reenable
    previous_apply = ENV["APPLY"]
    ENV["APPLY"] = apply ? "1" : nil
    original = $stdout
    buffer = StringIO.new
    $stdout = buffer
    task.invoke
    buffer.string
  ensure
    $stdout = original
    ENV["APPLY"] = previous_apply
  end

  let(:d1) { Date.new(2026, 8, 1) }
  let(:d2) { Date.new(2026, 8, 2) }

  # Espace « tente » : le Bois (capacité 3 personnes/groupes).
  let(:bois) { Space.create!(code: "Bois", name: "Bois", capacity: 3) }

  # SpaceBooking VIVANT + son Stay (via le service courant), sans réservation.
  def build_space_booking(price_cents: 3_000, status: "confirmed", **attrs)
    sb = SpaceBooking.create!({
      firstname: "Tente",
      lastname: "Camper",
      email: "tente@example.com",
      from_date: d1,
      to_date: d2,
      status: status,
      price_cents: price_cents
    }.merge(attrs))
    Stays::EnsureForSpaceBooking.call(sb)
    sb
  end

  def reserve(space_booking, space, date)
    SpaceReservation.create!(space_booking: space_booking, space: space, date: date)
  end

  context "SpaceBooking 100 % espace tente, 2 nuits à 30 € (people déduit = 2)" do
    it "le convertit en CampingBooking tente 2 personnes, nuits/prix/total conservés" do
      sb = build_space_booking(price_cents: 3_000) # 30 € = 2 nuits × 2 pers × 7,50 €
      reserve(sb, bois, d1)
      reserve(sb, bois, d2)
      stay = sb.stay
      total_before = stay.total_amount_cents

      expect(SpaceReservation.where(space: bois, deleted_at: nil).count).to eq(2)

      expect { run_task(apply: true) }.to change(CampingBooking, :count).by(1)

      camping = CampingBooking.last
      expect(camping.kind).to eq("tente")
      expect(camping.people).to eq(2) # 3000 / (2 × 750)
      # 2 jours consécutifs → [d1, d2+1) = 2 nuits.
      expect(camping.from_date).to eq(d1)
      expect(camping.to_date).to eq(d2 + 1)
      expect(camping.price_cents).to eq(3_000) # prix historique conservé tel quel
      expect(camping.firstname).to eq("Tente")
      expect(camping.status).to eq("confirmed")

      # Camping rattaché au MÊME séjour ; total du séjour INCHANGÉ.
      expect(camping.stay).to eq(stay)
      expect(stay.reload.total_amount_cents).to eq(total_before)

      # SpaceBooking soft-deleté, plus aucune SpaceReservation vivante.
      expect(SpaceBooking.find_by(id: sb.id)).to be_nil
      expect(SpaceBooking.with_deleted { SpaceBooking.unscoped.find(sb.id).deleted_at }).to be_present
      expect(SpaceReservation.where(space_booking_id: sb.id, deleted_at: nil)).to be_empty
      expect(SpaceReservation.where(space: bois, deleted_at: nil).count).to eq(0)

      # StayItem du camping vivant, StayItem du SpaceBooking retiré.
      expect(StayItem.where(bookable: camping).count).to eq(1)
      expect(StayItem.where(bookable_type: "SpaceBooking", bookable_id: sb.id).count).to eq(0)
    end
  end

  context "prix qui ne tombe pas juste (20 € / 2 nuits → 1,33 pers)" do
    # Décision Michael 2026-07-21 : on convertit QUAND MÊME — personnes
    # arrondies au plus proche (≥ 1), PRIX HISTORIQUE conservé (totaux
    # intacts), et le cas est listé au rapport pour relecture.
    it "convertit avec personnes arrondies et prix conservé, listé au rapport" do
      sb = build_space_booking(price_cents: 2_000) # 2000 / 1500 = 1,33 → arrondi 1
      reserve(sb, bois, d1)
      reserve(sb, bois, d2)

      output = nil
      expect { output = run_task(apply: true) }.to change(CampingBooking, :count).by(1)

      camping = CampingBooking.order(:id).last
      expect(camping.people).to eq(1)
      expect(camping.price_cents).to eq(2_000) # prix historique conservé
      expect(SpaceBooking.find_by(id: sb.id)).to be_nil # soft-deleté
      expect(output).to match(/personnes ARRONDIES/i)
      expect(output).to match(/space_booking #{sb.id}/)
    end
  end

  context "SpaceBooking mixte (tente + salle)" do
    it "n'y touche pas et le rapporte en skipped_mixed" do
      grande_salle = Space.create!(code: "GS", name: "Grande Salle", capacity: 1)
      sb = build_space_booking(price_cents: 3_000)
      reserve(sb, bois, d1)
      reserve(sb, grande_salle, d1)

      output = nil
      expect { output = run_task(apply: true) }.not_to change(CampingBooking, :count)

      expect(SpaceBooking.find_by(id: sb.id)).to be_present
      expect(SpaceReservation.where(space_booking_id: sb.id, deleted_at: nil).count).to eq(2)
      expect(output).to match(/mixtes.*#{sb.id}/)
    end
  end

  context "DRY-RUN (par défaut)" do
    it "n'écrit rien" do
      sb = build_space_booking(price_cents: 3_000)
      reserve(sb, bois, d1)
      reserve(sb, bois, d2)

      expect { run_task(apply: false) }.not_to change(CampingBooking, :count)
      expect(StayItem.where(bookable_type: "CampingBooking").count).to eq(0)
      expect(SpaceBooking.find_by(id: sb.id)).to be_present
      expect(SpaceReservation.where(space_booking_id: sb.id, deleted_at: nil).count).to eq(2)
    end
  end

  context "idempotence" do
    it "un second passage après APPLY ne convertit plus rien" do
      sb = build_space_booking(price_cents: 3_000)
      reserve(sb, bois, d1)
      reserve(sb, bois, d2)

      run_task(apply: true)

      output = nil
      expect { output = run_task(apply: true) }.not_to change(CampingBooking, :count)
      expect(output).to match(/Convertis en camping \(tente\)\s+:\s+0/)
    end
  end
end
