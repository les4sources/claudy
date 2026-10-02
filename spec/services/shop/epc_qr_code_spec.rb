require "rails_helper"

# Epic #359, phase 3 — le QR bancaire EPC069-12 d'un carnet.
RSpec.describe Shop::EpcQrCode do
  let(:settings) do
    ShopSetting.create!(iban: "BE68 5390 0754 7034", bic: "gkcc bebb", beneficiary_name: "Fondation Les 4 Sources")
  end

  it "produit le payload EPC exact : montant vide, communication du carnet" do
    qr = described_class.new(communication: "EPICERIE", settings: settings)

    expect(qr.payload).to eq(
      "BCD\n002\n1\nSCT\nGKCCBEBB\nFondation Les 4 Sources\nBE68539007547034\n\n\n\nEPICERIE"
    )
  end

  it "accepte un BIC absent (facultatif en version 002)" do
    settings.update!(bic: nil)
    expect(described_class.new(communication: "PAIN", settings: settings).payload.lines.map(&:chomp))
      .to eq(["BCD", "002", "1", "SCT", "", "Fondation Les 4 Sources", "BE68539007547034", "", "", "", "PAIN"])
  end

  it "borne la communication à 140 caractères" do
    qr = described_class.new(communication: "X" * 200, settings: settings)
    expect(qr.payload.lines.last.length).to eq(140)
  end

  it "refuse de produire un QR sans coordonnées bancaires" do
    qr = described_class.new(communication: "EPICERIE", settings: ShopSetting.new)
    expect(qr).not_to be_configured
    expect { qr.payload }.to raise_error(Shop::EpcQrCode::NotConfigured)
  end

  it "rend un SVG inline, sans prologue XML" do
    svg = described_class.new(communication: "EPICERIE", settings: settings).to_svg
    expect(svg).to start_with("<svg")
    expect(svg).to include('class="epc-qr"', "viewBox")
  end
end
