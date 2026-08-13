# == Schema Information
#
# Table name: payments
#
#  id                         :uuid             not null, primary key
#  amount_cents               :integer          default(0), not null
#  deleted_at                 :datetime
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
