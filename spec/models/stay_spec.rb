require "rails_helper"

RSpec.describe Stay, type: :model do
  let(:customer) { Customer.create!(email: "stay@example.com", customer_type: "individual") }

  def booking(from:, to:, price_cents: 0, status: "confirmed")
    Booking.create!(firstname: "Stay", from_date: from, to_date: to, adults: 1,
                    status: status, price_cents: price_cents)
  end

  describe "associations" do
    it "belongs to a customer and has many stay items" do
      stay = Stay.create!(customer: customer)
      b = booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3))
      stay.stay_items.create!(bookable: b)
      expect(stay.customer).to eq(customer)
      expect(stay.bookables).to contain_exactly(b)
    end
  end

  describe "#payments (read-derived, §11.6)" do
    it "returns the payments of its Booking items" do
      stay = Stay.create!(customer: customer)
      b = booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3))
      stay.stay_items.create!(bookable: b)
      # Donnée LEGACY : un Payment relié à son Booking mais SANS stay_id (état
      # d'avant le verrouillage Phase 4). On contourne la validation pour
      # reproduire fidèlement l'état en base et prouver que la branche « union par
      # booking_id » de Stay#payments reste couverte.
      payment = Payment.new(booking: b, amount_cents: 5_000, status: "paid", payment_method: "card")
      payment.save!(validate: false)

      expect(stay.payments).to contain_exactly(payment)
    end

    it "returns no payments for a stay made only of space bookings" do
      stay = Stay.create!(customer: customer)
      sb = SpaceBooking.create!(firstname: "Salle", from_date: Date.new(2026, 7, 1),
                                to_date: Date.new(2026, 7, 1), status: "confirmed")
      stay.stay_items.create!(bookable: sb)

      expect(stay.payments).to be_empty
    end

    # issue #26 — lien direct dénormalisé Payment -> Stay
    it "returns payments linked directly via stay_id" do
      stay = Stay.create!(customer: customer)
      b = booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3))
      payment = Payment.create!(booking: b, stay: stay, amount_cents: 5_000,
                                status: "pending", payment_method: "card")

      expect(stay.payments).to contain_exactly(payment)
    end

    it "n'duplique pas un paiement relié à la fois via stay_id et via son Booking" do
      stay = Stay.create!(customer: customer)
      b = booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3))
      stay.stay_items.create!(bookable: b)
      payment = Payment.create!(booking: b, stay: stay, amount_cents: 5_000,
                                status: "paid", payment_method: "card")

      expect(stay.payments).to contain_exactly(payment)
    end
  end

  describe "#recompute_aggregates!" do
    it "derives min arrival, max departure and summed amount from its items" do
      stay = Stay.create!(customer: customer)
      stay.stay_items.create!(bookable: booking(from: Date.new(2026, 7, 5), to: Date.new(2026, 7, 8), price_cents: 30_000))
      stay.stay_items.create!(bookable: booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3), price_cents: 20_000))

      stay.recompute_aggregates!

      expect(stay.arrival_date).to eq(Date.new(2026, 7, 1))
      expect(stay.departure_date).to eq(Date.new(2026, 7, 8))
      expect(stay.total_amount_cents).to eq(50_000)
    end
  end

  describe "#recompute_aggregates! avec prix imposé (epic #81, Phase 3)" do
    it "impose le total = override tout en gardant les dates de la composition" do
      stay = Stay.create!(customer: customer, price_override_cents: 99_900)
      stay.stay_items.create!(bookable: booking(from: Date.new(2026, 7, 5), to: Date.new(2026, 7, 8), price_cents: 30_000))

      stay.recompute_aggregates!

      expect(stay.total_amount_cents).to eq(99_900)         # override, pas 30 000
      expect(stay.arrival_date).to eq(Date.new(2026, 7, 5)) # dates toujours dérivées des items
      expect(stay.departure_date).to eq(Date.new(2026, 7, 8))
    end

    it "reprend le total de la composition quand l'override est retiré" do
      stay = Stay.create!(customer: customer, price_override_cents: 99_900)
      stay.stay_items.create!(bookable: booking(from: Date.new(2026, 7, 5), to: Date.new(2026, 7, 8), price_cents: 30_000))
      stay.recompute_aggregates!
      expect(stay.total_amount_cents).to eq(99_900)

      stay.update!(price_override_cents: nil)
      stay.recompute_aggregates!
      expect(stay.total_amount_cents).to eq(30_000)
    end

    it "fait suivre l'exigible et le solde depuis le total imposé" do
      stay = Stay.create!(customer: customer, price_override_cents: 50_000)
      b = booking(from: Date.new(2026, 7, 5), to: Date.new(2026, 7, 8), price_cents: 30_000)
      stay.stay_items.create!(bookable: b)
      Payment.create!(booking: b, stay: stay, amount_cents: 20_000, status: "paid", payment_method: "card")
      stay.recompute_aggregates!

      expect(stay.payable_amount_cents).to eq(50_000) # = total imposé (aucune activité pending)
      expect(stay.balance_due_cents).to eq(30_000)    # 50 000 imposés − 20 000 encaissés
    end
  end

  describe "scopes" do
    it "separates current/future stays from past ones" do
      future = Stay.create!(customer: customer, arrival_date: Date.today + 5, departure_date: Date.today + 10)
      past = Stay.create!(customer: customer, arrival_date: Date.today - 10, departure_date: Date.today - 5)

      expect(Stay.current_and_future).to include(future)
      expect(Stay.current_and_future).not_to include(past)
      expect(Stay.past).to include(past)
      expect(Stay.past).not_to include(future)
    end
  end

  describe "jeton public (#26 Phase 1)" do
    it "génère un token à la création" do
      expect(Stay.create!(customer: customer).token).to be_present
    end

    it "génère des tokens distincts" do
      first = Stay.create!(customer: customer)
      second = Stay.create!(customer: customer)
      expect(first.token).not_to eq(second.token)
    end

    it "refuse un token dupliqué" do
      existing = Stay.create!(customer: customer)
      duplicate = Stay.new(customer: customer, token: existing.token)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token]).to be_present
    end
  end

  describe "#set_payment_status (#26 Phase 1)" do
    let(:stay) { Stay.create!(customer: customer, total_amount_cents: 20_000) }

    def pay(cents, status)
      b = booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3), price_cents: 20_000)
      stay.stay_items.create!(bookable: b)
      Payment.create!(booking: b, stay: stay, amount_cents: cents, status: status, payment_method: "card")
    end

    it "démarre à pending" do
      expect(stay.payment_status).to eq("pending")
    end

    it "passe en paid quand les paiements encaissés couvrent le total" do
      pay(20_000, "paid")
      stay.set_payment_status
      expect(stay.reload.payment_status).to eq("paid")
      expect(stay).to be_paid
    end

    it "passe en partially_paid quand l'encaissé est insuffisant" do
      pay(5_000, "paid")
      stay.set_payment_status
      expect(stay.reload.payment_status).to eq("partially_paid")
    end

    it "reste pending tant que le paiement n'est pas encaissé" do
      pay(20_000, "pending")
      stay.set_payment_status
      expect(stay.reload.payment_status).to eq("pending")
    end

    it "reste pending pour un séjour à 0 € sans paiement (pas de bascule 0 >= 0)" do
      zero = Stay.create!(customer: customer, total_amount_cents: 0)
      zero.set_payment_status
      expect(zero.reload.payment_status).to eq("pending")
    end

    it "refuse un statut de paiement inconnu" do
      stay.payment_status = "refunded"
      expect(stay).not_to be_valid
      expect(stay.errors[:payment_status]).to be_present
    end
  end

  describe "#source (Q9 — AC-T2-22 / AC-T2-22b)" do
    it "défaute sur 'reservation' quand non précisé" do
      stay = Stay.create!(customer: customer)
      expect(stay.source).to eq("reservation")
    end

    it "est distinct de legacy_origin (clé d'import/dédup)" do
      stay = Stay.create!(customer: customer, source: "reservation", legacy_origin: "booking:42")
      expect(stay.source).to eq("reservation")
      expect(stay.legacy_origin).to eq("booking:42")
    end

    it "refuse une valeur de canal inconnue" do
      stay = Stay.new(customer: customer, source: "carrier-pigeon")
      expect(stay).not_to be_valid
      expect(stay.errors[:source]).to be_present
    end

    it "filtre par canal via le scope from_source" do
      reservation = Stay.create!(customer: customer, source: "reservation")
      tally = Stay.create!(customer: customer, source: "tally_legacy")
      expect(Stay.from_source("reservation")).to include(reservation)
      expect(Stay.from_source("reservation")).not_to include(tally)
      expect(Stay.from_source(nil)).to include(reservation, tally)
    end
  end

  describe "#recompute_aggregates! avec activités (epic #55, Phase 1)" do
    let(:stay) { Stay.create!(customer: customer) }
    let(:experience) { Experience.create!(name: "Atelier pain", fixed_price_cents: 5_000, price_cents: 1_500) }
    let(:availability) do
      # Date volontairement HORS de la fenêtre de l'hébergement pour prouver que
      # les activités ne déplacent pas les bornes du séjour.
      ExperienceAvailability.create!(experience: experience, available_on: Date.new(2026, 7, 10), starts_at: "10:00")
    end

    before do
      stay.stay_items.create!(bookable: booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3), price_cents: 20_000))
    end

    it "ajoute les activités ACTIVES au total, sans toucher aux dates" do
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 3)

      stay.recompute_aggregates!

      # 20 000 (hébergement) + 5 000 (forfait fixe) + 1 500 × 3 (participants) = 29 500
      expect(stay.total_amount_cents).to eq(29_500)
      # Dates dérivées des SEULS bookables — l'activité du 10/07 ne les bouge pas.
      expect(stay.arrival_date).to eq(Date.new(2026, 7, 1))
      expect(stay.departure_date).to eq(Date.new(2026, 7, 3))
    end

    it "exclut les activités annulées" do
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 3, status: "cancelled")

      stay.recompute_aggregates!

      expect(stay.total_amount_cents).to eq(20_000) # hébergement seul
    end
  end

  describe "#amount_due_cents / #settled? (epic #55, Phase 1)" do
    let(:stay) { Stay.create!(customer: customer, total_amount_cents: 20_000) }

    def pay(cents, status)
      b = booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3), price_cents: 20_000)
      stay.stay_items.create!(bookable: b)
      Payment.create!(booking: b, stay: stay, amount_cents: cents, status: status, payment_method: "card")
    end

    it "montant dû = total tant que rien n'est encaissé" do
      expect(stay.amount_paid_cents).to eq(0)
      expect(stay.amount_due_cents).to eq(20_000)
      expect(stay).not_to be_settled
    end

    it "réduit le dû du montant de l'acompte encaissé" do
      pay(5_000, "paid")
      expect(stay.amount_paid_cents).to eq(5_000)
      expect(stay.amount_due_cents).to eq(15_000)
      expect(stay).not_to be_settled
    end

    it "ignore les paiements non encaissés dans le calcul du dû" do
      pay(20_000, "pending")
      expect(stay.amount_paid_cents).to eq(0)
      expect(stay.amount_due_cents).to eq(20_000)
      expect(stay).not_to be_settled
    end

    it "est soldé quand l'encaissé couvre le total" do
      pay(20_000, "paid")
      expect(stay.amount_due_cents).to eq(0)
      expect(stay).to be_settled
    end

    it "un séjour à 0 € sans paiement n'est PAS soldé (garde-fou 0 >= 0)" do
      zero = Stay.create!(customer: customer, total_amount_cents: 0)
      expect(zero.amount_due_cents).to eq(0)
      expect(zero).not_to be_settled
    end
  end

  describe "#balance_due_cents / montant exigible (epic #55, Phase 3)" do
    let(:experience) { Experience.create!(name: "Atelier pain", fixed_price_cents: 5_000, price_cents: 1_500) }
    let(:availability) do
      ExperienceAvailability.create!(experience: experience, available_on: Date.new(2026, 7, 10), starts_at: "10:00")
    end

    # Total prévu posé directement = hébergement 20 000 + confirmée 8 000 + pending 6 500.
    let(:stay) { Stay.create!(customer: customer, total_amount_cents: 34_500) }

    before do
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed") # 8 000
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 1, status: "pending")   # 6 500
    end

    it "exclut les activités pending de l'assiette exigible, inclut les confirmed" do
      expect(stay.experiences_pending_amount_cents).to eq(6_500)
      expect(stay.experiences_confirmed_amount_cents).to eq(8_000)
      # Assiette exigible = total prévu − pending = 34 500 − 6 500 = 28 000.
      expect(stay.payable_amount_cents).to eq(28_000)
    end

    it "déduit l'encaissé du reste dû exigible" do
      Payment.create!(stay: stay, amount_cents: 10_000, status: "paid", payment_method: "card")
      expect(stay.balance_due_cents).to eq(18_000) # 28 000 − 10 000
      expect(stay).to be_payable_now
    end

    it "n'est plus exigible quand l'encaissé couvre l'assiette exigible (pending exclue)" do
      Payment.create!(stay: stay, amount_cents: 28_000, status: "paid", payment_method: "card")
      expect(stay.balance_due_cents).to eq(0)
      expect(stay).not_to be_payable_now
    end

    it "distingue TOTAL PRÉVU (amount_due, pending inclus) et EXIGIBLE (balance_due, pending exclu)" do
      Payment.create!(stay: stay, amount_cents: 28_000, status: "paid", payment_method: "card")
      # Exigible couvert…
      expect(stay.balance_due_cents).to eq(0)
      # …mais le total prévu (qui compte la pending) montre encore 6 500 à venir.
      expect(stay.amount_due_cents).to eq(6_500)
    end

    it "marque le séjour paid dès que l'exigible est couvert, malgré une activité pending restante" do
      Payment.create!(stay: stay, amount_cents: 28_000, status: "paid", payment_method: "card")
      stay.set_payment_status
      expect(stay.reload.payment_status).to eq("paid")
    end
  end
end
