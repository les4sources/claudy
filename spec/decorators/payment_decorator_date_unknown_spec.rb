require "rails_helper"

# Paiements repris de l'ancienne facturation des espaces (rake
# `space_bookings:billing_to_payments`, passée le 2026-07-21) : sans date de
# paiement, ils s'affichaient tous au 21/07 (Michael 2026-10-15).
RSpec.describe PaymentDecorator, "date d'un paiement repris sans date" do
  let(:customer) { Customer.create!(email: "reprise@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer, status: "confirmed") }
  let(:space_booking) do
    SpaceBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                         from_date: Date.new(2025, 5, 10), to_date: Date.new(2025, 5, 10),
                         status: "confirmed")
  end

  def payment(**attrs)
    Payment.create!({ stay: stay, amount_cents: 47_500, status: "paid",
                      payment_method: "bank_transfer" }.merge(attrs))
  end

  it "affiche « Date non disponible » pour un paiement repris d'une réservation d'espace" do
    repris = payment(space_booking: space_booking)

    expect(repris.date_unknown?).to be(true)
    expect(repris.decorate.payment_date).to eq("Date non disponible")
    expect(repris.decorate.payment_date_title).to include("ancienne réservation d'espace")
  end

  it "reprend la date saisie dès qu'on en a posé une" do
    repris = payment(space_booking: space_booking, paid_on: Date.new(2025, 5, 3))

    expect(repris.date_unknown?).to be(false)
    expect(repris.decorate.payment_date(format: :ddmmyyyy)).to eq(I18n.l(Date.new(2025, 5, 3), format: :ddmmyyyy))
  end

  it "garde la date de saisie pour un paiement ordinaire sans date" do
    ordinaire = payment

    expect(ordinaire.date_unknown?).to be(false)
    expect(ordinaire.decorate.payment_date).to eq(I18n.l(ordinaire.created_at.to_date))
  end
end
