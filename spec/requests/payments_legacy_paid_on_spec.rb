require "rails_helper"

RSpec.describe "Paiement (canal booking) — champ date", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user) { User.create!(email: "legacy-date@les4sources.be", password: "password123") }
  before { sign_in user }

  it "rend le champ date dans le formulaire d'édition niché sous booking" do
    customer = Customer.create!(email: "legacy@example.com", first_name: "Léa", last_name: "Legacy")
    booking = Booking.create!(firstname: "L", adults: 2, from_date: Date.today + 3,
                              to_date: Date.today + 5, status: "confirmed", price_cents: 10_000)
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")
    payment = Payment.create!(booking: booking, stay: stay, amount_cents: 5_000,
                              status: "paid", payment_method: "bank_transfer")

    get edit_booking_payment_path(booking, payment), headers: { "Turbo-Frame" => "modal" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="payment[paid_on]"')
    expect(response.body).to include("Date du paiement (optionnel)")
  end

  it "enregistre la date depuis ce formulaire" do
    customer = Customer.create!(email: "legacy2@example.com", first_name: "Luc", last_name: "Legacy")
    booking = Booking.create!(firstname: "L", adults: 2, from_date: Date.today + 3,
                              to_date: Date.today + 5, status: "confirmed", price_cents: 10_000)
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")
    payment = Payment.create!(booking: booking, stay: stay, amount_cents: 5_000,
                              status: "paid", payment_method: "bank_transfer")

    patch booking_payment_path(booking, payment), params: {
      payment: { amount: "50", payment_method: "bank_transfer", paid_on: "2026-08-03" }
    }

    expect(payment.reload.paid_on).to eq(Date.new(2026, 8, 3))
  end
end
