require "rails_helper"

# Epic #248, phase 2 — ce qu'un relevé de dépôt-vente garantit.
RSpec.describe ConsignmentReport do
  let!(:eline) do
    Consignor.create!(name: "Eline", email: "eline@example.com", settlement_mode: "invoice",
                      commission_percent: 20)
  end

  def build_report(attributes = {})
    described_class.new({ consignor: eline, period_month: Date.new(2026, 8, 1) }.merge(attributes))
  end

  it "se donne un jeton long et non devinable" do
    report = build_report
    report.save!

    expect(report.token).to be_present
    expect(report.token.length).to be >= 24
  end

  it "ramène la période au premier du mois" do
    report = build_report(period_month: Date.new(2026, 8, 17))
    report.save!

    expect(report.period_month).to eq(Date.new(2026, 8, 1))
  end

  it "refuse un second relevé pour le même artisan et le même mois" do
    build_report.save!
    doublon = build_report(period_month: Date.new(2026, 8, 20))

    expect(doublon).not_to be_valid
    expect(doublon.errors[:consignor_id]).to be_present
  end

  it "laisse deux artisans déclarer le même mois" do
    build_report.save!
    autre = Consignor.create!(name: "Bruno", email: "bruno@example.com",
                              settlement_mode: "invoice", commission_percent: 30)

    expect(described_class.new(consignor: autre, period_month: Date.new(2026, 8, 1))).to be_valid
  end

  describe "les totaux vivants" do
    let!(:report) do
      r = build_report
      r.save!
      r.consignment_report_lines.create!(label: "Savon", quantity: 3, unit_price_cents: 650)
      r.consignment_report_lines.create!(label: "Baume", quantity: 1, unit_price_cents: 1_200)
      r.reload
    end

    it "somme les lignes et applique la commission du contrat" do
      expect(report.live_gross_cents).to eq(3_150)
      expect(report.live_commission_cents).to eq(630)
      expect(report.live_net_cents).to eq(2_520)
    end

    # Une fois vérifié, ce sont les colonnes figées qui parlent — jamais un
    # recalcul, sinon un changement de taux réécrirait le passé.
    it "montre les colonnes figées dès qu'il est vérifié" do
      report.update!(status: "verified", gross_cents: 3_150, commission_cents: 630, net_cents: 2_520)
      eline.update!(commission_percent: 50)

      expect(report.reload.displayed_commission_cents).to eq(630)
      expect(report.displayed_net_cents).to eq(2_520)
    end
  end

  describe "la modification par l'artisan" do
    it "reste ouverte tant que rien n'est vérifié" do
      expect(build_report(status: "requested").editable_by_consignor?).to be(true)
      expect(build_report(status: "declared").editable_by_consignor?).to be(true)
    end

    it "se ferme dès la vérification" do
      expect(build_report(status: "verified").editable_by_consignor?).to be(false)
      expect(build_report(status: "settled").editable_by_consignor?).to be(false)
    end
  end
end

RSpec.describe ConsignmentReportLine do
  let!(:eline) { Consignor.create!(name: "Eline", settlement_mode: "invoice", commission_percent: 20) }
  let!(:report) { ConsignmentReport.create!(consignor: eline, period_month: Date.new(2026, 8, 1)) }

  it "calcule le montant plutôt que de le demander" do
    line = report.consignment_report_lines.create!(label: "Savon", quantity: 3, unit_price_cents: 650)

    expect(line.amount_cents).to eq(1_950)
  end

  it "refuse une quantité nulle ou négative" do
    expect(report.consignment_report_lines.build(label: "Savon", quantity: 0)).not_to be_valid
    expect(report.consignment_report_lines.build(label: "Savon", quantity: -2)).not_to be_valid
  end

  it "refuse une ligne sans libellé" do
    expect(report.consignment_report_lines.build(quantity: 1, unit_price_cents: 100)).not_to be_valid
  end
end
