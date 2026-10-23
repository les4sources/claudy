require "rails_helper"

# L'espace des partenaires (Michael, 2026-10-22) : une adresse email et les
# fiches qui la portent, un rôle par fiche.
RSpec.describe Portal::Partner do
  let!(:eline) do
    Consignor.create!(name: "Eline", settlement_mode: "invoice",
                      email: "Eline@Example.com", portal_enabled: true)
  end

  it "reconnaît l'artisane dont l'espace est ouvert, sans tenir compte de la casse" do
    partner = described_class.for_email("  eline@example.COM ")

    expect(partner.consignor).to eq(eline)
    expect(partner.roles).to eq([:consignment])
    expect(partner).to be_role(:consignment)
    expect(partner.name).to eq("Eline")
  end

  it "n'ouvre rien à une adresse sans fiche" do
    expect(described_class.for_email("ana@example.com")).to be_nil
    expect(described_class.for_email("")).to be_nil
  end

  it "n'ouvre rien quand l'espace de l'artisane est fermé" do
    eline.update!(portal_enabled: false)

    expect(described_class.for_email("eline@example.com")).to be_nil
  end
end
