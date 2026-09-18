require "rails_helper"

# Issue #339 — le passage quotidien. Il ne fait rien sans clé d'API, et vérifie
# chaque party active sinon.
RSpec.describe SyncTranchesDeViePartiesJob do
  around do |example|
    url, key = ENV["TRANCHESDEVIE_API_URL"], ENV["TRANCHESDEVIE_API_KEY"]
    example.run
    ENV["TRANCHESDEVIE_API_URL"] = url
    ENV["TRANCHESDEVIE_API_KEY"] = key
  end

  let(:customer) { Customer.create!(email: "job@example.com", customer_type: "organization", organization_name: "Scouts") }
  let(:stay) { Stay.create!(customer: customer, status: "confirmed") }

  it "ne fait rien et ne sort pas sur le réseau sans clé d'API" do
    tdv_env_off!
    expect(described_class.perform_now).to eq(:skipped)
    expect(a_request(:any, //)).not_to have_been_made
  end

  it "vérifie chaque party active" do
    tdv_env!
    stub_tdv_order(tdv_order(id: 1234))
    TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)

    stub_tdv_order(tdv_order(id: 1234, refunded: true, refunded_at: "2026-09-25T09:00:00Z"))
    service = described_class.perform_now

    expect(service.checked).to eq(1)
    expect(service.changed).to eq(1)
    expect(stay.reload.party_reservations.first.status).to eq("refunded")
  end
end
