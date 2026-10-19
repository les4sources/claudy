require "rails_helper"

# Issue #339 — ce qui est annulé ou remboursé là-bas sort du total et de
# l'encaissé ici, mais reste VISIBLE : la compta doit voir l'historique.
RSpec.describe TranchesDeVie::SyncPartyReservations do
  around do |example|
    url, key = ENV["TRANCHESDEVIE_API_URL"], ENV["TRANCHESDEVIE_API_KEY"]
    tdv_env!
    example.run
    ENV["TRANCHESDEVIE_API_URL"] = url
    ENV["TRANCHESDEVIE_API_KEY"] = key
  end

  let(:customer) { Customer.create!(email: "sync@example.com", customer_type: "organization", organization_name: "Scouts") }
  let(:stay) { Stay.create!(customer: customer, status: "confirmed") }

  def attach!(id: 1234)
    LinenOrder.find_or_create_by!(stay: stay, kind: "double_bed") { |o| o.quantity = 1; o.price_cents = 50_000 }
    stub_tdv_order(tdv_order(id: id))
    TranchesDeVie::AttachPartyReservation.new(stay: stay).run(id)
    stay.reload.party_reservations.first
  end

  it "ne touche à rien quand la commande n'a pas bougé" do
    reservation = attach!
    stub_tdv_order(tdv_order(id: 1234))

    service = described_class.new
    expect(service.run).to be(true)
    expect(service.checked).to eq(1)
    expect(service.changed).to eq(0)
    expect(reservation.reload.status).to eq("active")
    expect(reservation.synced_at).to be_present
    expect(stay.reload.total_amount_cents).to eq(77_000)
  end

  it "sort une party remboursée du total et de l'encaissé, sans la faire disparaître" do
    reservation = attach!
    stub_tdv_order(tdv_order(id: 1234, refunded: true, refunded_at: "2026-09-25T09:00:00Z"))

    service = described_class.new
    expect(service.run).to be(true)
    expect(service.changed).to eq(1)

    expect(reservation.reload.status).to eq("refunded")
    expect(reservation.external_refunded_at).to be_present
    expect(reservation.payment.reload.status).to eq("refunded")

    expect(stay.reload.total_amount_cents).to eq(50_000)
    expect(stay.amount_paid_cents).to eq(0)
    # Elle reste lisible : c'est tout l'intérêt pour la compta.
    expect(stay.party_reservations).to include(reservation)
  end

  it "traite une annulation comme un remboursement" do
    reservation = attach!
    stub_tdv_order(tdv_order(id: 1234, cancelled: true))

    described_class.new.run
    expect(reservation.reload.status).to eq("cancelled")
    expect(reservation.payment.reload.status).to eq("refunded")
    expect(stay.reload.total_amount_cents).to eq(50_000)
  end

  it "traite une commande disparue (404) comme une annulation" do
    reservation = attach!
    stub_tdv_order_missing(1234)

    described_class.new.run
    expect(reservation.reload.status).to eq("cancelled")
    expect(reservation.external_refunded_at).to be_present
    expect(stay.reload.total_amount_cents).to eq(50_000)
  end

  it "note une party injoignable et passe à la suivante sans rien changer" do
    reservation = attach!
    stub_request(:get, %r{#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders/1234}).to_timeout

    service = described_class.new
    expect(service.run).to be(true)
    expect(service.failures.map(&:first)).to eq([reservation.id])
    expect(reservation.reload.status).to eq("active")
    expect(stay.reload.total_amount_cents).to eq(77_000)
  end

  it "ajoute le paiement d'une party rattachée avant d'être réglée" do
    LinenOrder.create!(stay: stay, kind: "double_bed", quantity: 1, price_cents: 50_000)
    stub_tdv_order(tdv_unpaid_order(id: 1234))
    TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)
    reservation = stay.reload.party_reservations.first
    expect(stay.amount_paid_cents).to eq(0)

    stub_tdv_order(tdv_order(id: 1234, payment_method: "cash", paid_at: "2026-10-10T21:00:00Z"))
    service = described_class.new
    expect(service.run).to be(true)
    expect(service.changed).to eq(1)

    expect(reservation.reload.paid).to be(true)
    expect(reservation.payment.status).to eq("paid")
    expect(reservation.payment.amount_cents).to eq(27_000)
    expect(reservation.payment.paid_on).to eq(Date.new(2026, 10, 10))
    expect(stay.reload.total_amount_cents).to eq(77_000)
    expect(stay.amount_paid_cents).to eq(27_000)

    # Un deuxième passage ne double pas le paiement.
    described_class.new.run
    expect(Payment.where(payment_method: Payment::TRANCHESDEVIE_METHOD).count).to eq(1)
  end

  it "retire le paiement d'une party redevenue non payée là-bas, sans la sortir du total" do
    reservation = attach!
    payment = reservation.payment
    expect(stay.reload.amount_paid_cents).to eq(27_000)

    # Le boulanger annule le pointage : la commande redevient due.
    stub_tdv_order(tdv_unpaid_order(id: 1234))
    service = described_class.new
    expect(service.run).to be(true)
    expect(service.changed).to eq(1)

    expect(reservation.reload.paid).to be(false)
    expect(reservation.status).to eq("active")
    expect(reservation.payment).to be_nil
    expect(Payment.with_deleted { Payment.find(payment.id) }.deleted_at).to be_present
    expect(stay.reload.total_amount_cents).to eq(77_000)
    expect(stay.amount_paid_cents).to eq(0)

    # Pointée à nouveau : le paiement revient, une seule fois.
    stub_tdv_order(tdv_order(id: 1234, payment_method: "cash", paid_at: "2026-10-20T21:00:00Z"))
    described_class.new.run
    expect(reservation.reload.payment.amount_cents).to eq(27_000)
    expect(stay.reload.amount_paid_cents).to eq(27_000)
    expect(Payment.where(payment_method: Payment::TRANCHESDEVIE_METHOD).count).to eq(1)
  end

  it "suit le prix revu là-bas, paiement miroir compris" do
    reservation = attach!
    stub_tdv_order(tdv_order(id: 1234, total_cents: 30_000))

    service = described_class.new
    expect(service.run).to be(true)
    expect(service.changed).to eq(1)
    expect(reservation.reload.price_cents).to eq(30_000)
    expect(reservation.payment.amount_cents).to eq(30_000)
    expect(stay.reload.total_amount_cents).to eq(80_000)
    expect(stay.amount_paid_cents).to eq(30_000)
  end

  it "ne regarde que le séjour demandé avec for_stay" do
    reservation = attach!
    autre_stay = Stay.create!(customer: customer, status: "confirmed")
    stub_tdv_order(tdv_order(id: 4321))
    TranchesDeVie::AttachPartyReservation.new(stay: autre_stay).run(4321)

    stub_tdv_order(tdv_order(id: 1234, refunded: true, refunded_at: "2026-09-25T09:00:00Z"))
    service = described_class.for_stay(stay)
    expect(service.run).to be(true)
    expect(service.checked).to eq(1)
    expect(reservation.reload.status).to eq("refunded")
    expect(autre_stay.party_reservations.first.status).to eq("active")
  end

  it "refuse de partir sans clé d'API" do
    tdv_env_off!
    service = described_class.new
    expect(service.run).to be(false)
    expect(service.error_message).to match(/non configurée/)
  end
end
