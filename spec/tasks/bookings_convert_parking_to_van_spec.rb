require "rails_helper"
require "rake"

RSpec.describe "bookings:convert_parking_to_van", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("bookings:convert_parking_to_van")
  end

  # Exécute la tâche et renvoie sa sortie (rapport ventilé), silençée du flux de
  # test. `apply: true` pose APPLY=1 le temps de l'invocation.
  def run_task(apply: false)
    task = Rake::Task["bookings:convert_parking_to_van"]
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

  let(:from) { Date.new(2026, 8, 1) }
  let(:to)   { Date.new(2026, 8, 3) } # 2 nuits : réservations sur d1 (08-01) et d2 (08-02)

  # Gîte « Espace camping-cars » + sa chambre Parking (code métier PKG).
  let!(:camping_lodging) do
    lodging = Lodging.create!(name: "Espace camping-cars", price_night_cents: 1_500)
    lodging.rooms << pkg_room
    lodging
  end
  let(:pkg_room) { Room.create!(code: "PKG", name: "Parking", level: -1) }

  # Booking VIVANT + son Stay (via le service courant), sans réservation.
  def build_booking(price_cents: 3_000, status: "confirmed", **attrs)
    booking = Booking.create!({
      firstname: "Van",
      lastname: "Camper",
      email: "van@example.com",
      from_date: from,
      to_date: to,
      adults: 1,
      status: status,
      price_cents: price_cents,
      lodging: camping_lodging
    }.merge(attrs))
    Stays::EnsureForBooking.call(booking)
    booking
  end

  # Réserve une chambre sur chaque nuit [from, to).
  def reserve_nights(booking, room)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
  end

  context "Booking 100 % chambre Parking sur 2 nuits" do
    it "le convertit en VanBooking 1 véhicule, nuits/prix/total conservés, chambre libérée" do
      booking = build_booking(price_cents: 3_000)
      reserve_nights(booking, pkg_room)
      stay = booking.stay
      total_before = stay.total_amount_cents

      # Pré-condition : la chambre Parking est bien réservée ces nuits-là.
      expect(Reservation.where(room: pkg_room).count).to eq(2)

      expect { run_task(apply: true) }.to change(VanBooking, :count).by(1)

      van = VanBooking.last
      expect(van.vehicles).to eq(1)
      # Bornes nuits copiées telles quelles depuis le Booking.
      expect(van.from_date).to eq(from)
      expect(van.to_date).to eq(to)
      expect(van.price_cents).to eq(3_000) # prix historique conservé tel quel
      expect(van.firstname).to eq("Van")
      expect(van.status).to eq("confirmed")

      # Van rattaché au MÊME séjour ; total du séjour INCHANGÉ.
      expect(van.stay).to eq(stay)
      expect(stay.reload.total_amount_cents).to eq(total_before)

      # Booking soft-deleté, réservations soft-deletées en cascade (chambre libre).
      expect(Booking.find_by(id: booking.id)).to be_nil # masqué par le default scope
      expect(Booking.with_deleted { Booking.unscoped.find(booking.id).deleted_at }).to be_present
      expect(Reservation.where(room: pkg_room).count).to eq(0) # plus aucune vivante

      # StayItem du van vivant, StayItem du Booking retiré.
      expect(StayItem.where(bookable: van).count).to eq(1)
      expect(StayItem.where(bookable_type: "Booking", bookable_id: booking.id).count).to eq(0)
    end
  end

  context "Booking mixte (Parking + autre chambre)" do
    it "n'y touche pas et le rapporte en skipped_mixed" do
      autre_chambre = Room.create!(code: "CH1", name: "Chambre 1", level: 1)
      booking = build_booking
      reserve_nights(booking, pkg_room)
      reserve_nights(booking, autre_chambre)

      output = nil
      expect { output = run_task(apply: true) }.not_to change(VanBooking, :count)

      # Intact : ni soft-delete, ni réservations détruites.
      expect(Booking.find_by(id: booking.id)).to be_present
      expect(Reservation.where(booking_id: booking.id).count).to eq(4)

      expect(output).to match(/mixtes.*#{booking.id}/)
    end
  end

  context "DRY-RUN (par défaut)" do
    it "n'écrit rien" do
      booking = build_booking
      reserve_nights(booking, pkg_room)

      expect { run_task(apply: false) }.not_to change(VanBooking, :count)
      expect(StayItem.where(bookable_type: "VanBooking").count).to eq(0)
      expect(Booking.find_by(id: booking.id)).to be_present
      expect(Reservation.where(room: pkg_room).count).to eq(2)
    end
  end

  context "idempotence" do
    it "un second passage après APPLY ne convertit plus rien" do
      booking = build_booking
      reserve_nights(booking, pkg_room)

      run_task(apply: true)

      output = nil
      expect { output = run_task(apply: true) }.not_to change(VanBooking, :count)
      expect(output).to match(/Convertis en van\s+:\s+0/)
    end
  end
end
