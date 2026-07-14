# == Schema Information
#
# Table name: payments
#
#  booking_id                 :bigint           not null
#  payment_method             :string
#  status                     :string
#  deleted_at                 :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  amount_cents               :integer          default(0), not null
#  stripe_checkout_session_id :string
#  stripe_payment_intent_id   :string
#  id                         :uuid             not null, primary key
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
  # paiement (la validation de présence de `stay_id` arrive en Phase 4).
  it "accepte un paiement sans booking, rattaché à un séjour" do
    stay = Stay.create!(customer: customer, source: "reservation", status: "pending",
                        total_amount_cents: 10_000)
    payment = Payment.new(stay: stay, amount_cents: 5_000, status: "pending",
                          payment_method: "card")

    expect(payment).to be_valid
    expect(payment.booking).to be_nil
  end

  it "accepte un stay optionnel (issue #26)" do
    payment = Payment.create!(booking: booking, amount_cents: 5_000, status: "pending",
                              payment_method: "card")
    expect(payment.stay).to be_nil

    stay = Stay.create!(customer: customer)
    payment.update!(stay: stay)
    expect(payment.reload.stay).to eq(stay)
  end
end
