require "rails_helper"

RSpec.describe Vies::Client do
  let(:url) { "https://ec.europa.eu/taxation_customs/vies/rest-api/ms/BE/vat/0123456749" }

  it "confirme un numéro connu et rend la raison sociale" do
    stub_request(:get, url).to_return(status: 200, body: { isValid: true, name: "LES 4 SOURCES  ASBL", userError: "VALID" }.to_json)

    result = described_class.check("BE0123456749")
    expect(result).to be_valid
    expect(result.name).to eq("LES 4 SOURCES ASBL")
  end

  it "dit inconnu quand VIES répond INVALID" do
    stub_request(:get, url).to_return(status: 200, body: { isValid: false, userError: "INVALID" }.to_json)

    expect(described_class.check("BE0123456749")).to be_invalid
  end

  it "ne lève jamais quand VIES est en panne" do
    stub_request(:get, url).to_return(status: 200, body: { isValid: false, userError: "MS_UNAVAILABLE" }.to_json)
    expect(described_class.check("BE0123456749")).to be_unavailable

    stub_request(:get, url).to_timeout
    expect(described_class.check("BE0123456749")).to be_unavailable

    stub_request(:get, url).to_return(status: 500, body: "oops")
    expect(described_class.check("BE0123456749")).to be_unavailable
  end
end
