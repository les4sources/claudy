require "rails_helper"

# Issue #339 — la ligne « séjour » de la file de facturation doit inclure la
# Pizza Party : sans ça, la facture partirait sans elle.
RSpec.describe Invoicing::Queue, "Pizza Party (issue #339)" do
  around do |example|
    url, key = ENV["TRANCHESDEVIE_API_URL"], ENV["TRANCHESDEVIE_API_KEY"]
    tdv_env!
    example.run
    ENV["TRANCHESDEVIE_API_URL"] = url
    ENV["TRANCHESDEVIE_API_KEY"] = key
  end

  let(:customer) { Customer.create!(email: "facture@example.com", customer_type: "organization", organization_name: "Scouts") }
  let(:stay) do
    Stay.create!(customer: customer, status: "confirmed", invoice_status: "requested",
                 arrival_date: Date.new(2026, 10, 8), departure_date: Date.new(2026, 10, 11))
  end

  before do
    LinenOrder.create!(stay: stay, kind: "double_bed", quantity: 1, price_cents: 50_000)
    stay.recompute_aggregates!
    stub_tdv_order(tdv_order(id: 1234))
    TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)
  end

  def stay_line
    described_class.new.requested.find { |l| l.kind == "stay" && l.id == stay.id }
  end

  it "compte la party dans le montant de la ligne séjour" do
    expect(stay_line).to be_present
    expect(stay_line.price_cents).to eq(77_000)
  end

  it "ne compte plus une party remboursée" do
    stub_tdv_order(tdv_order(id: 1234, refunded: true, refunded_at: "2026-09-25T09:00:00Z"))
    TranchesDeVie::SyncPartyReservations.for_stay(stay).run

    expect(stay_line.price_cents).to eq(50_000)
  end
end
