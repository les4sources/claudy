require "rails_helper"

# Issue #339 — rattacher une Pizza Party payée ajoute son montant au total du
# séjour ET à l'encaissé : un séjour soldé le reste.
RSpec.describe TranchesDeVie::AttachPartyReservation do
  around do |example|
    url, key = ENV["TRANCHESDEVIE_API_URL"], ENV["TRANCHESDEVIE_API_KEY"]
    tdv_env!
    example.run
    ENV["TRANCHESDEVIE_API_URL"] = url
    ENV["TRANCHESDEVIE_API_KEY"] = key
  end

  let(:customer) { Customer.create!(email: "attach@example.com", customer_type: "organization", organization_name: "Scouts") }
  let(:stay) { Stay.create!(customer: customer, status: "confirmed") }

  # Une base de 500 € portée par un VRAI élément du séjour : `recompute_aggregates!`
  # dérive le total de la composition, un `total_amount_cents` posé à la main
  # serait écrasé au premier recalcul.
  before do
    LinenOrder.create!(stay: stay, kind: "double_bed", quantity: 1, price_cents: 50_000)
    stay.recompute_aggregates!
  end

  it "crée le miroir et son paiement, et fait bouger total et encaissé du même montant" do
    stub_tdv_order(tdv_order(id: 1234))
    service = described_class.new(stay: stay)

    expect { service.run(1234) }
      .to change { stay.reload.total_amount_cents }.by(27_000)
      .and change { stay.amount_paid_cents }.by(27_000)

    reservation = service.party_reservation
    expect(reservation.external_number).to eq("TV-20261009-1234")
    expect(reservation.held_on).to eq(Date.new(2026, 10, 9))
    expect(reservation.group_name).to eq("Scouts de Namur")
    expect(reservation.persons).to eq(18)
    expect(reservation.price_cents).to eq(27_000)
    expect(reservation.external_admin_url).to be_present
    expect(reservation.payload).to be_present

    payment = reservation.payment
    expect(payment.payment_method).to eq(Payment::TRANCHESDEVIE_METHOD)
    expect(payment.status).to eq("paid")
    expect(payment.amount_cents).to eq(27_000)
    expect(payment.paid_on).to eq(Date.new(2026, 9, 20))
    expect(payment.stay).to eq(stay)
  end

  it "laisse soldé un séjour qui l'était" do
    Payment.create!(stay: stay, amount_cents: 50_000, status: "paid", payment_method: "bank_transfer")
    stay.set_payment_status
    expect(stay.reload).to be_settled

    stub_tdv_order(tdv_order(id: 1234))
    expect(described_class.new(stay: stay).run(1234)).to be(true)

    expect(stay.reload).to be_settled
    expect(stay.payment_status).to eq("paid")
    expect(stay.balance_due_cents).to eq(0)
  end

  it "rend la party exigible (elle n'est pas déduite de l'assiette)" do
    stub_tdv_order(tdv_order(id: 1234))
    described_class.new(stay: stay).run(1234)

    expect(stay.reload.payable_amount_cents).to eq(77_000)
  end

  it "refuse de rattacher deux fois la même party" do
    stub_tdv_order(tdv_order(id: 1234))
    described_class.new(stay: stay).run(1234)

    service = described_class.new(stay: stay)
    expect(service.run(1234)).to be(false)
    expect(service.error_message).to eq(described_class::ALREADY_ATTACHED)
  end

  it "refuse une party remboursée" do
    stub_tdv_order(tdv_order(id: 1234, refunded: true, refunded_at: "2026-09-25T09:00:00Z"))

    service = described_class.new(stay: stay)
    expect(service.run(1234)).to be(false)
    expect(service.error_message).to eq(described_class::NOT_PAID)
    expect(PartyReservation.count).to eq(0)
  end

  it "remonte une erreur réseau sans rien écrire" do
    stub_request(:get, %r{#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders}).to_timeout

    service = described_class.new(stay: stay)
    expect(service.run(1234)).to be(false)
    expect(service.error_message).to match(/n'a pas répondu à temps/)
    expect(PartyReservation.count).to eq(0)
    expect(stay.reload.total_amount_cents).to eq(50_000)
  end
end
