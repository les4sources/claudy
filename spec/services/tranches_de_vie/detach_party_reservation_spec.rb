require "rails_helper"

# Issue #339 — détacher retire la party du total ET son paiement de l'encaissé.
# Rien n'est détruit sèchement : la compta doit pouvoir revenir en arrière.
RSpec.describe TranchesDeVie::DetachPartyReservation do
  around do |example|
    url, key = ENV["TRANCHESDEVIE_API_URL"], ENV["TRANCHESDEVIE_API_KEY"]
    tdv_env!
    example.run
    ENV["TRANCHESDEVIE_API_URL"] = url
    ENV["TRANCHESDEVIE_API_KEY"] = key
  end

  let(:customer) { Customer.create!(email: "detach@example.com", customer_type: "organization", organization_name: "Scouts") }
  let(:stay) { Stay.create!(customer: customer, status: "confirmed") }

  before do
    LinenOrder.create!(stay: stay, kind: "double_bed", quantity: 1, price_cents: 50_000)
    stay.recompute_aggregates!
    stub_tdv_order(tdv_order(id: 1234))
    TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)
  end

  it "ramène le total et l'encaissé à leur valeur d'avant" do
    reservation = stay.reload.party_reservations.first
    expect(stay.total_amount_cents).to eq(77_000)

    expect(described_class.new(party_reservation: reservation).run).to be(true)

    expect(stay.reload.total_amount_cents).to eq(50_000)
    expect(stay.amount_paid_cents).to eq(0)
    expect(stay.party_reservations).to be_empty
  end

  it "soft-delete la party et son paiement (rien n'est détruit)" do
    reservation = stay.reload.party_reservations.first
    payment_id = reservation.payment_id

    described_class.new(party_reservation: reservation).run

    expect(PartyReservation.find_by(id: reservation.id)).to be_nil
    expect(PartyReservation.unscoped.find(reservation.id).deleted_at).to be_present
    expect(Payment.find_by(id: payment_id)).to be_nil
    expect(Payment.unscoped.find(payment_id).deleted_at).to be_present
  end

  it "recalcule le statut de paiement du séjour" do
    reservation = stay.reload.party_reservations.first
    described_class.new(party_reservation: reservation).run

    expect(stay.reload.payment_status).to eq("pending")
  end
end
