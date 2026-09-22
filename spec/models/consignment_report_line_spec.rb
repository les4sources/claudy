require "rails_helper"

# Epic #359, phase 1 — une ligne de relevé peut pointer un article du catalogue
# et dire comment le client a payé.
RSpec.describe ConsignmentReportLine do
  let(:consignor) { Consignor.create!(name: "Eline", settlement_mode: "invoice") }
  let(:report) { ConsignmentReport.create!(consignor: consignor, period_month: Date.current.beginning_of_month) }
  let(:savon) do
    CatalogItem.create!(name: "Savon", channel: "craft", unit: "piece", consignor: consignor).tap do |item|
      item.catalog_prices.create!(active_from: Date.current - 1, member_price_cents: 500, public_price_cents: 600)
    end
  end

  describe "le mode de paiement" do
    it "accepte les trois modes de la feuille" do
      described_class::PAYMENT_METHODS.each do |method|
        line = report.consignment_report_lines.new(label: "Savon", quantity: 1,
                                                   unit_price_cents: 600, payment_method: method)
        expect(line).to be_valid
      end
    end

    it "reste facultatif — les lignes du lien mensuel n'en portent pas" do
      line = report.consignment_report_lines.new(label: "Savon", quantity: 1, unit_price_cents: 600)

      expect(line).to be_valid
    end

    it "refuse un mode inconnu" do
      line = report.consignment_report_lines.new(label: "Savon", quantity: 1,
                                                 unit_price_cents: 600, payment_method: "bitcoin")

      expect(line).not_to be_valid
    end
  end

  describe "la reprise depuis l'article" do
    it "copie le libellé et le prix PUBLIC du jour à la création" do
      line = report.consignment_report_lines.create!(catalog_item: savon, quantity: 2)

      expect(line.label).to eq("Savon")
      expect(line.unit_price_cents).to eq(600)
      expect(line.amount_cents).to eq(1_200)
    end

    # La copie n'a lieu QU'À la création : passer une ligne à zéro se fait
    # ensuite, et le prix de l'article ne revient pas par la fenêtre.
    it "ne recopie pas le prix quand la ligne est modifiée après coup" do
      line = report.consignment_report_lines.create!(catalog_item: savon, quantity: 1)
      line.update!(unit_price_cents: 0)

      expect(line.reload.unit_price_cents).to eq(0)
    end

    it "ne touche ni au libellé ni au prix que l'artisan a tapés" do
      line = report.consignment_report_lines.create!(catalog_item: savon, label: "Savon au lait d'ânesse",
                                                     quantity: 1, unit_price_cents: 750)

      expect(line.label).to eq("Savon au lait d'ânesse")
      expect(line.unit_price_cents).to eq(750)
    end

    # Le libellé est une COPIE, pas une référence : renommer l'article ne
    # réécrit jamais ce qui a été déclaré le mois dernier.
    it "ne suit pas l'article renommé après coup" do
      line = report.consignment_report_lines.create!(catalog_item: savon, quantity: 1)
      savon.update!(name: "Savon de Marseille")

      expect(line.reload.label).to eq("Savon")
    end

    it "se rabat sur le prix sourcier quand l'article n'a pas de prix public" do
      sans_public = CatalogItem.create!(name: "Bougie", channel: "craft", unit: "piece", consignor: consignor)
      sans_public.catalog_prices.create!(active_from: Date.current - 1, member_price_cents: 400)

      line = report.consignment_report_lines.create!(catalog_item: sans_public, quantity: 1)

      expect(line.unit_price_cents).to eq(400)
    end
  end

  it "ne retient que les lignes payées en espèces" do
    especes = report.consignment_report_lines.create!(label: "Savon", quantity: 1,
                                                      unit_price_cents: 600, payment_method: "cash")
    report.consignment_report_lines.create!(label: "Bougie", quantity: 1,
                                            unit_price_cents: 400, payment_method: "qr")

    expect(report.consignment_report_lines.paid_in_cash).to contain_exactly(especes)
  end
end
