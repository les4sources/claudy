require "rails_helper"
require "rake"

RSpec.describe "spaces:convert_parking_to_van", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("spaces:convert_parking_to_van")
  end

  # Exécute la tâche et renvoie sa sortie (rapport ventilé), en la silençant du
  # flux de test. `apply: true` pose APPLY=1 le temps de l'invocation.
  def run_task(apply: false)
    task = Rake::Task["spaces:convert_parking_to_van"]
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

  # Espace Parking (code métier PKG), capacité 1 (une seule occupation/jour) pour
  # pouvoir vérifier le veto de dispo avant/après conversion.
  let(:pkg) { Space.create!(code: "PKG", name: "Parking", capacity: 1) }

  # SpaceBooking VIVANT + son Stay (via le service courant), sans réservation.
  def build_space_booking(price_cents: 3_000, status: "confirmed", **attrs)
    sb = SpaceBooking.create!({
      firstname: "Van",
      lastname: "Camper",
      email: "van@example.com",
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

  context "SpaceBooking 100 % Parking sur 2 jours" do
    it "le convertit en VanBooking 1 véhicule, nuits correctes, prix et total conservés" do
      sb = build_space_booking(price_cents: 3_000)
      reserve(sb, pkg, d1)
      reserve(sb, pkg, d2)
      stay = sb.stay
      total_before = stay.total_amount_cents

      # Pré-condition : l'espace Parking est bien occupé (veto actif) ces jours-là.
      expect(pkg.available_on?(d1)).to be false
      expect(pkg.available_on?(d2)).to be false

      expect { run_task(apply: true) }.to change(VanBooking, :count).by(1)

      van = VanBooking.last
      expect(van.vehicles).to eq(1)
      # 2 jours de parking consécutifs → [d1, d2+1) = 2 nuits.
      expect(van.from_date).to eq(d1)
      expect(van.to_date).to eq(d2 + 1)
      expect(van.price_cents).to eq(3_000) # prix historique conservé tel quel
      expect(van.firstname).to eq("Van")
      expect(van.status).to eq("confirmed")

      # Van rattaché au MÊME séjour ; total du séjour INCHANGÉ.
      expect(van.stay).to eq(stay)
      expect(stay.reload.total_amount_cents).to eq(total_before)

      # SpaceBooking soft-deleté, plus aucune SpaceReservation vivante.
      expect(SpaceBooking.find_by(id: sb.id)).to be_nil # masqué par le default scope
      expect(SpaceBooking.with_deleted { SpaceBooking.unscoped.find(sb.id).deleted_at }).to be_present
      expect(SpaceReservation.where(space_booking_id: sb.id, deleted_at: nil)).to be_empty

      # StayItem du van vivant, StayItem du SpaceBooking retiré.
      expect(StayItem.where(bookable: van).count).to eq(1)
      expect(StayItem.where(bookable_type: "SpaceBooking", bookable_id: sb.id).count).to eq(0)

      # Calendrier / veto : l'espace Parking est de nouveau libre.
      expect(pkg.available_on?(d1)).to be true
      expect(pkg.available_on?(d2)).to be true
    end
  end

  context "SpaceBooking mixte (Parking + Grande Salle)" do
    it "n'y touche pas et le rapporte en skipped_mixed" do
      grande_salle = Space.create!(code: "GS", name: "Grande Salle", capacity: 1)
      sb = build_space_booking
      reserve(sb, pkg, d1)
      reserve(sb, grande_salle, d1)

      output = nil
      expect { output = run_task(apply: true) }.not_to change(VanBooking, :count)

      # Intact : ni soft-delete, ni réservations détruites.
      expect(SpaceBooking.find_by(id: sb.id)).to be_present
      expect(SpaceReservation.where(space_booking_id: sb.id, deleted_at: nil).count).to eq(2)

      expect(output).to match(/mixtes.*#{sb.id}/)
    end
  end

  context "DRY-RUN (par défaut)" do
    it "n'écrit rien" do
      sb = build_space_booking
      reserve(sb, pkg, d1)
      reserve(sb, pkg, d2)

      expect { run_task(apply: false) }.not_to change(VanBooking, :count)
      expect(StayItem.where(bookable_type: "VanBooking").count).to eq(0)
      expect(SpaceBooking.find_by(id: sb.id)).to be_present
      expect(SpaceReservation.where(space_booking_id: sb.id, deleted_at: nil).count).to eq(2)
    end
  end

  context "idempotence" do
    it "un second passage après APPLY ne convertit plus rien" do
      sb = build_space_booking
      reserve(sb, pkg, d1)
      reserve(sb, pkg, d2)

      run_task(apply: true)

      output = nil
      expect { output = run_task(apply: true) }.not_to change(VanBooking, :count)
      expect(output).to match(/Convertis en van\s+:\s+0/)
    end
  end
end
