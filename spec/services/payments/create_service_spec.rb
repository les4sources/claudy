require "rails_helper"

RSpec.describe Payments::CreateService do
  def build_booking(**attrs)
    Booking.create!({
      firstname: "Marc",
      email: "marc@example.com",
      from_date: Date.new(2026, 9, 1),
      to_date: Date.new(2026, 9, 3),
      adults: 1,
      status: "confirmed",
      price_cents: 20_000
    }.merge(attrs))
  end

  def payment_params(amount: 50, method: "cash")
    ActionController::Parameters.new(payment: { amount: amount, payment_method: method })
  end

  it "crée un paiement admin porteur d'un stay_id (et conserve booking_id)" do
    booking = build_booking
    service = described_class.new(booking_id: booking.id)

    expect(service.run(payment_params)).to be(true)

    payment = service.payment.reload
    expect(payment.stay_id).to be_present
    expect(payment.booking_id).to eq(booking.id)
    expect(payment.stay).to eq(booking.reload.stay)
  end

  it "réutilise le Stay existant du booking plutôt que d'en créer un autre" do
    booking = build_booking
    stay = Stays::EnsureForBooking.call(booking)

    service = described_class.new(booking_id: booking.id)
    expect { service.run(payment_params) }.not_to change(Stay, :count)

    expect(service.payment.reload.stay_id).to eq(stay.id)
  end

  it "backfille un Stay pour un vieux booking qui n'en avait pas, puis relie le paiement" do
    booking = build_booking
    expect(booking.stay).to be_nil

    service = described_class.new(booking_id: booking.id)
    expect(service.run(payment_params)).to be(true)

    expect(booking.reload.stay).to be_present
    expect(service.payment.reload.stay_id).to eq(booking.stay.id)
  end

  it "met à jour le statut de paiement du booking" do
    booking = build_booking(price_cents: 10_000)
    service = described_class.new(booking_id: booking.id)

    service.run(payment_params(amount: 100, method: "cash")) # 100 € = 10 000 cents, payé

    expect(booking.reload.payment_status).to eq("paid")
  end
end
