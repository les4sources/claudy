require "rails_helper"

# Fusion de séjours (epic #81, Phase 2). Calqué sur le spec de
# Customers::MergeService : on construit deux Stay saisis séparément (ancien
# Booking + ancien SpaceBooking d'un même séjour client), on fusionne, et on
# vérifie que la cible absorbe toutes les occupations tandis que les sources
# vidées sont soft-deletées.
RSpec.describe Stays::MergeService, type: :service do
  def make_customer(email, **attrs)
    Customer.create!({ email: email, customer_type: "individual" }.merge(attrs))
  end

  def make_stay(customer:, **attrs)
    Stay.create!({
      customer: customer,
      source: "manual",
      status: "confirmed",
      arrival_date: Date.new(2026, 8, 1),
      departure_date: Date.new(2026, 8, 3),
      total_amount_cents: 0
    }.merge(attrs))
  end

  def make_booking(**attrs)
    Booking.create!({
      firstname: "Zoé", lastname: "Durand", email: "booking@example.com",
      from_date: Date.new(2026, 8, 1), to_date: Date.new(2026, 8, 3),
      adults: 2, status: "confirmed", price_cents: 30_000
    }.merge(attrs))
  end

  def make_space_booking(**attrs)
    SpaceBooking.create!({
      firstname: "Zoé", lastname: "Durand", email: "space@example.com",
      from_date: Date.new(2026, 8, 4), to_date: Date.new(2026, 8, 6),
      status: "confirmed", price_cents: 20_000
    }.merge(attrs))
  end

  def attach(stay, bookable)
    StayItem.create!(stay: stay, bookable: bookable)
  end

  let(:experience) { Experience.create!(name: "Atelier pain", fixed_price_cents: 5_000, price_cents: 1_500) }
  let(:availability) do
    ExperienceAvailability.create!(experience: experience, available_on: Date.new(2026, 8, 5), starts_at: "10:00")
  end

  describe "fusion Booking + SpaceBooking (2 séjours → 1)" do
    let(:customer) { make_customer("client@example.com") }
    let(:target) { make_stay(customer: customer) }
    let(:source) { make_stay(customer: customer, arrival_date: Date.new(2026, 8, 4), departure_date: Date.new(2026, 8, 6)) }

    let(:booking) { make_booking }
    let(:space_booking) { make_space_booking }

    before do
      attach(target, booking)
      attach(source, space_booking)
      Payment.create!(stay: target, amount_cents: 10_000, status: "paid", payment_method: "card")
      Payment.create!(stay: source, amount_cents: 5_000, status: "paid", payment_method: "transfer")
    end

    it "porte les 2 occupations, recalcule dates/total, regroupe les paiements et soft-delete la source" do
      service = described_class.new(target: target, sources: [source])
      expect(service.run).to be_truthy

      # Les 2 occupations vivent désormais sur la cible.
      expect(target.reload.bookables).to contain_exactly(booking, space_booking)

      # Dates = union (min arrivée / max départ) de toutes les occupations.
      expect(target.arrival_date).to eq(Date.new(2026, 8, 1))
      expect(target.departure_date).to eq(Date.new(2026, 8, 6))

      # Total recalculé sans double-compte = 30 000 + 20 000.
      expect(target.total_amount_cents).to eq(50_000)

      # Paiements regroupés sur la cible = 10 000 + 5 000 encaissés.
      expect(target.amount_paid_cents).to eq(15_000)
      # Solde exigible = total − encaissé = 50 000 − 15 000.
      expect(target.balance_due_cents).to eq(35_000)
      expect(target.payment_status).to eq("partially_paid")

      # Source vidée puis soft-deletée.
      expect(Stay.find_by(id: source.id)).to be_nil
      expect(Stay.unscoped.find(source.id).deleted_at).to be_present
    end

    it "trace le changement de stay_id des occupations via PaperTrail" do
      described_class.new(target: target, sources: [source]).run

      moved_item = StayItem.find_by(bookable: space_booking)
      expect(moved_item.stay_id).to eq(target.id)
      expect(moved_item.versions.last.object_changes).to include("stay_id")

      moved_payment = Payment.find_by(amount_cents: 5_000)
      expect(moved_payment.stay_id).to eq(target.id)
      expect(moved_payment.versions.last.object_changes).to include("stay_id")
    end
  end

  # Décision figée (epic #81, Phase 3) : à la fusion, l'override de la CIBLE est
  # CONSERVÉ (le recompute de la cible fusionnée l'honore) ; les overrides des
  # SOURCES tombent (leur montant réel a déjà été absorbé dans les items migrés).
  describe "prix imposé (epic #81, Phase 3)" do
    let(:customer) { make_customer("override@example.com") }

    it "conserve l'override de la CIBLE comme total du séjour fusionné" do
      target = make_stay(customer: customer, price_override_cents: 88_000)
      source = make_stay(customer: customer, arrival_date: Date.new(2026, 8, 4), departure_date: Date.new(2026, 8, 6))
      attach(target, make_booking(price_cents: 30_000))
      attach(source, make_space_booking(price_cents: 20_000))

      expect(described_class.new(target: target, sources: [source]).run).to be_truthy
      expect(target.reload.total_amount_cents).to eq(88_000) # override conservé, pas 50 000
    end

    it "ignore l'override d'une SOURCE (montant réel déjà absorbé dans les items)" do
      target = make_stay(customer: customer)
      source = make_stay(customer: customer, price_override_cents: 99_999,
                         arrival_date: Date.new(2026, 8, 4), departure_date: Date.new(2026, 8, 6))
      attach(target, make_booking(price_cents: 30_000))
      attach(source, make_space_booking(price_cents: 20_000))

      expect(described_class.new(target: target, sources: [source]).run).to be_truthy
      expect(target.reload.total_amount_cents).to eq(50_000) # somme des items, override source ignoré
    end
  end

  describe "clients différents" do
    it "conserve le client de la cible (la cible gagne)" do
      target_customer = make_customer("cible@example.com")
      source_customer = make_customer("source@example.com")
      target = make_stay(customer: target_customer)
      source = make_stay(customer: source_customer)
      attach(target, make_booking)
      attach(source, make_space_booking)

      described_class.new(target: target, sources: [source]).run

      expect(target.reload.customer_id).to eq(target_customer.id)
      # L'occupation migrée suit la cible (donc son client).
      expect(StayItem.find_by(bookable_type: "SpaceBooking").stay.customer_id).to eq(target_customer.id)
    end
  end

  describe "migration des éléments non calendaires" do
    it "déplace MealOrder et ExperienceBooking vers la cible" do
      customer = make_customer("repas@example.com")
      target = make_stay(customer: customer)
      source = make_stay(customer: customer)
      attach(target, make_booking)

      meal = MealOrder.create!(stay: source, kind: "buffet", date: Date.new(2026, 8, 5), people: 4, price_cents: 4_000)
      exp_booking = ExperienceBooking.create!(experience_availability: availability, stay: source, participants: 2, status: "confirmed")

      expect(described_class.new(target: target, sources: [source]).run).to be_truthy

      expect(meal.reload.stay_id).to eq(target.id)
      expect(exp_booking.reload.stay_id).to eq(target.id)
      expect(target.reload.meal_orders).to include(meal)
      expect(target.experience_bookings).to include(exp_booking)
    end
  end

  describe "garde-fous" do
    let(:customer) { make_customer("guard@example.com") }

    it "refuse une fusion sans source (1 seul séjour)" do
      target = make_stay(customer: customer)
      service = described_class.new(target: target, sources: [])
      expect(service.run).to be(false)
      expect(service.error_message).to be_present
    end

    it "refuse si la cible figure parmi les sources" do
      target = make_stay(customer: customer)
      service = described_class.new(target: target, sources: [target])
      expect(service.run).to be(false)
      expect(service.error_message).to be_present
    end

    it "refuse une source déjà soft-deletée (idempotence : pas de corruption)" do
      target = make_stay(customer: customer)
      source = make_stay(customer: customer)
      attach(source, make_space_booking)
      source.soft_delete!(validate: false)

      service = described_class.new(target: target, sources: [Stay.unscoped.find(source.id)])
      expect(service.run).to be(false)
      expect(service.error_message).to be_present
      # L'occupation de la source n'a pas migré vers la cible (elle reste sur la
      # source — soft-deletée en cascade avec elle, donc lue en unscoped).
      expect(StayItem.unscoped.find_by(bookable_type: "SpaceBooking").stay_id).to eq(source.id)
    end

    it "refuse une cible déjà soft-deletée" do
      target = make_stay(customer: customer)
      source = make_stay(customer: customer)
      target.soft_delete!(validate: false)

      service = described_class.new(target: Stay.unscoped.find(target.id), sources: [source])
      expect(service.run).to be(false)
      expect(service.error_message).to be_present
    end
  end

  describe "cache d'association préchargé (régression)" do
    # Le contrôleur charge les séjours avec includes(stay_items: :bookable) :
    # sans le reload d'absorb!, la cascade dependent: :destroy du soft-delete
    # relisait le cache et supprimait les items pourtant déjà migrés.
    it "ne re-supprime pas les items migrés quand stay_items est préchargé" do
      customer = make_customer("preload@example.com")
      target = make_stay(customer: customer)
      source = make_stay(customer: customer)
      attach(target, make_booking)
      attach(source, make_space_booking)

      preloaded = Stay.where(id: [target.id, source.id]).includes(stay_items: :bookable).to_a
      preloaded_target = preloaded.find { |s| s.id == target.id }
      preloaded_source = preloaded.find { |s| s.id == source.id }

      expect(described_class.new(target: preloaded_target, sources: [preloaded_source]).run).to be_truthy
      expect(target.reload.stay_items.count).to eq(2)
    end
  end

  describe "consolidation des notes" do
    let(:customer) { make_customer("notes@example.com") }
    let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }

    it "réunit UNE note interne et UNE note publique consolidées sur le survivant, sans vider les bookables" do
      target = make_stay(customer: customer, notes: "Note du séjour cible")
      source = make_stay(customer: customer, notes: "Note du séjour source",
                         arrival_date: Date.new(2026, 8, 4), departure_date: Date.new(2026, 8, 6))

      booking = make_booking(notes: "Note interne hébergement", lodging: lodging)
      booking.public_notes = "<div>Bienvenue à La Hulotte</div>"
      booking.save!

      space_booking = make_space_booking(notes: "Note interne espace")
      space_booking.public_notes = "<div>Salle prête dès 14h</div>"
      space_booking.save!

      attach(target, booking)
      attach(source, space_booking)

      expect(described_class.new(target: target, sources: [source]).run).to be_truthy
      target.reload

      # Note interne consolidée : tous les contenus + provenance.
      expect(target.notes).to include("Note du séjour cible")
      expect(target.notes).to include("Note du séjour source")
      expect(target.notes).to include("Note interne hébergement")
      expect(target.notes).to include("Note interne espace")
      expect(target.notes).to include("La Hulotte") # provenance du bookable

      # Note publique consolidée (HTML des deux bookables).
      html = target.public_notes.body.to_html
      expect(html).to include("Bienvenue à La Hulotte")
      expect(html).to include("Salle prête dès 14h")

      # Les bookables GARDENT leurs notes (rien ne se perd — principe P2).
      expect(booking.reload.notes).to eq("Note interne hébergement")
      expect(space_booking.reload.notes).to eq("Note interne espace")
      expect(space_booking.public_notes.body.to_plain_text).to include("Salle prête dès 14h")
    end

    it "laisse les notes du survivant inchangées quand il n'y a AUCUNE note nulle part" do
      target = make_stay(customer: customer)
      source = make_stay(customer: customer,
                         arrival_date: Date.new(2026, 8, 4), departure_date: Date.new(2026, 8, 6))
      attach(target, make_booking)
      attach(source, make_space_booking)

      expect(described_class.new(target: target, sources: [source]).run).to be_truthy
      expect(target.reload.notes).to be_blank
      expect(target.public_notes.body).to be_blank
    end

    it "déduplique les contenus internes strictement identiques" do
      target = make_stay(customer: customer, notes: "Même note")
      source = make_stay(customer: customer, notes: "Même note",
                         arrival_date: Date.new(2026, 8, 4), departure_date: Date.new(2026, 8, 6))
      attach(target, make_booking(notes: "Même note", lodging: lodging))
      attach(source, make_space_booking)

      expect(described_class.new(target: target, sources: [source]).run).to be_truthy
      expect(target.reload.notes.scan("Même note").size).to eq(1)
    end
  end

  describe "intégrité transactionnelle" do
    it "ne modifie rien si une étape échoue en cours de route" do
      customer = make_customer("tx@example.com")
      target = make_stay(customer: customer)
      source = make_stay(customer: customer)
      attach(target, make_booking)
      space_booking = make_space_booking
      attach(source, space_booking)
      Payment.create!(stay: source, amount_cents: 5_000, status: "paid", payment_method: "card")

      # Simule une exception au recalcul final : tout doit être annulé (tout-ou-rien).
      allow(target).to receive(:recompute_aggregates!).and_raise(ActiveRecord::StatementInvalid.new("boom"))

      service = described_class.new(target: target, sources: [source])
      expect(service.run).to be(false)

      # Rien n'a bougé : occupation, paiement et source intacts.
      expect(StayItem.find_by(bookable: space_booking).stay_id).to eq(source.id)
      expect(Payment.find_by(amount_cents: 5_000).stay_id).to eq(source.id)
      expect(source.reload.deleted_at).to be_nil
      expect(target.reload.stay_items.count).to eq(1)
    end
  end
end
