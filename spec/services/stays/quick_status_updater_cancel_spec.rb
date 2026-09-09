require "rails_helper"

# Annulation d'un séjour (décision Michael 2026-09-08) : depuis qu'une
# pré-confirmation pose un acompte ET bloque les dates, « Annuler le séjour »
# doit aussi neutraliser cet acompte — sinon le lien Stripe reste payable et
# l'encaissement reconfirmerait un séjour annulé.
RSpec.describe Stays::QuickStatusUpdater, "annulation et paiements en attente" do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }
  let(:arrivee) { Date.today + 30 }
  let(:depart)  { Date.today + 32 }

  def sejour(status:)
    Stay.create!(customer: customer, source: "reservation", status: status,
                 arrival_date: arrivee, departure_date: depart, total_amount_cents: 74_500)
  end

  def acompte_pour(stay, status: "pending")
    Payment.create!(stay: stay, amount_cents: 37_250, status: status, payment_method: "card")
  end

  it "soft-delete l'acompte encore en attente d'un séjour pré-confirmé" do
    stay    = sejour(status: "pre_confirmed")
    acompte = acompte_pour(stay)

    expect(described_class.new(stay: stay, status: "canceled").run).to be(true)

    expect(stay.reload.status).to eq("canceled")
    expect(Payment.find_by(id: acompte.id)).to be_nil
    expect(Payment.with_deleted { Payment.find(acompte.id) }.deleted_at).to be_present
  end

  it "ne touche jamais un paiement encaissé" do
    stay     = sejour(status: "confirmed")
    encaisse = acompte_pour(stay, status: "paid")

    described_class.new(stay: stay, status: "canceled").run

    expect(Payment.find_by(id: encaisse.id)).to eq(encaisse)
  end

  it "laisse l'acompte intact sur une confirmation" do
    stay    = sejour(status: "pre_confirmed")
    acompte = acompte_pour(stay)

    described_class.new(stay: stay, status: "confirmed").run

    expect(Payment.find_by(id: acompte.id)).to eq(acompte)
  end
end
