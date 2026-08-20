# == Schema Information
#
# Table name: payments
#
#  id                         :uuid             not null, primary key
#  amount_cents               :integer          default(0), not null
#  deleted_at                 :datetime
#  paid_on                    :date
#  payment_method             :string
#  status                     :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  booking_id                 :bigint
#  coworking_pack_id          :bigint
#  space_booking_id           :bigint
#  stay_id                    :bigint
#  stripe_checkout_session_id :string
#  stripe_payment_intent_id   :string
#
# Indexes
#
#  index_payments_on_booking_id         (booking_id)
#  index_payments_on_coworking_pack_id  (coworking_pack_id)
#  index_payments_on_id                 (id) UNIQUE
#  index_payments_on_space_booking_id   (space_booking_id)
#  index_payments_on_stay_id            (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (booking_id => bookings.id)
#  fk_rails_...  (coworking_pack_id => coworking_packs.id)
#  fk_rails_...  (space_booking_id => space_bookings.id)
#  fk_rails_...  (stay_id => stays.id)
#
require 'rails_helper'

RSpec.describe Payment, type: :model do
  let(:customer) { Customer.create!(email: "pay@example.com", customer_type: "individual") }
  let(:booking) do
    Booking.create!(firstname: "Pay", from_date: Date.today, to_date: Date.today + 2,
                    adults: 1, status: "pending", price_cents: 10_000)
  end

  # Stay-first (epic #26, Phase 2) : le booking n'est plus l'ancre obligatoire du
  # paiement — un séjour sans hébergement n'en a pas. C'est le Stay qui porte le
  # paiement.
  it "accepte un paiement sans booking, rattaché à un séjour" do
    stay = Stay.create!(customer: customer, source: "reservation", status: "pending",
                        total_amount_cents: 10_000)
    payment = Payment.new(stay: stay, amount_cents: 5_000, status: "pending",
                          payment_method: "card")

    expect(payment).to be_valid
    expect(payment.booking).to be_nil
  end

  # Phase 4 (« verrouillage ») : le stay devient OBLIGATOIRE. Un Payment sans
  # stay_id est désormais invalide (inversion de la Phase 2 où il était optionnel).
  it "refuse un paiement sans séjour (verrouillage Phase 4)" do
    payment = Payment.new(booking: booking, amount_cents: 5_000, status: "pending",
                          payment_method: "card")

    expect(payment).not_to be_valid
    expect(payment.errors[:stay]).to be_present
    expect { payment.save! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  describe "#effective_date" do
    it "retombe sur la date de saisie quand aucune date d'encaissement n'est posée" do
      stay = Stay.create!(customer: customer, source: "reservation", status: "confirmed")
      payment = Payment.create!(stay: stay, amount_cents: 5_000, status: "paid",
                                payment_method: "cash")

      expect(payment.paid_on).to be_nil
      expect(payment.effective_date).to eq(payment.created_at.to_date)
    end

    it "préfère la date d'encaissement dès qu'elle est renseignée" do
      stay = Stay.create!(customer: customer, source: "reservation", status: "confirmed")
      payment = Payment.create!(stay: stay, amount_cents: 5_000, status: "paid",
                                payment_method: "cash", paid_on: Date.new(2026, 8, 3))

      expect(payment.effective_date).to eq(Date.new(2026, 8, 3))
    end
  end

  describe ".journalable" do
    def stay_with(status)
      Stay.create!(customer: customer, source: "reservation", status: status)
    end

    def payment_for(stay, status)
      Payment.create!(stay: stay, amount_cents: 5_000, status: status,
                      payment_method: "cash")
    end

    it "écarte tout ce qui pend sous un séjour en attente" do
      en_attente = stay_with("pending")
      encaisse = payment_for(en_attente, "paid")
      pendant = payment_for(en_attente, "pending")

      expect(Payment.journalable).not_to include(encaisse, pendant)
    end

    it "ne garde d'un séjour annulé que ce qui a été encaissé" do
      annule = stay_with("canceled")
      encaisse = payment_for(annule, "paid")
      pendant = payment_for(annule, "pending")

      expect(Payment.journalable).to include(encaisse)
      expect(Payment.journalable).not_to include(pendant)
    end

    it "traite l'orthographe historique « cancelled » comme une annulation" do
      annule = stay_with("cancelled")
      pendant = payment_for(annule, "pending")

      expect(Payment.journalable).not_to include(pendant)
    end

    it "garde tout d'un séjour confirmé" do
      confirme = stay_with("confirmed")
      pendant = payment_for(confirme, "pending")

      expect(Payment.journalable).to include(pendant)
    end

    it "garde un séjour au statut vide ou nul — la règle ne vise que pending et annulé" do
      vide = payment_for(stay_with(""), "pending")
      nul = payment_for(stay_with(nil), "pending")

      expect(Payment.journalable).to include(vide, nul)
    end

    it "n'écarte jamais un paiement sans séjour" do
      pack = CoworkingPack.create!(customer: customer, days_total: 5, payment_method: "card")
      sans_sejour = Payment.create!(coworking_pack: pack, amount_cents: 2_000,
                                    status: "pending", payment_method: "cash")

      expect(Payment.journalable).to include(sans_sejour)
    end
  end

  it "redevient valide dès qu'un séjour est rattaché" do
    stay = Stay.create!(customer: customer, source: "reservation", status: "pending",
                        total_amount_cents: 10_000)
    payment = Payment.new(booking: booking, stay: stay, amount_cents: 5_000,
                          status: "pending", payment_method: "card")

    expect(payment).to be_valid
    expect(payment.booking).to eq(booking)
    expect(payment.stay).to eq(stay)
  end
end
