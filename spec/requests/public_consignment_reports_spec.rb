require "rails_helper"

# Epic #248, phase 2 — la page à jeton de l'artisan. Aucune session, aucun
# Devise : c'est le lien du mail qui ouvre la porte.
RSpec.describe "Dépôt-vente — la déclaration de l'artisan", type: :request do
  let!(:eline) do
    Consignor.create!(name: "Eline", email: "eline@example.com", settlement_mode: "invoice",
                      commission_percent: 20)
  end
  let!(:report) { ConsignmentReport.create!(consignor: eline, period_month: Date.new(2026, 8, 1)) }

  describe "GET /depot-vente/:token" do
    it "ouvre la déclaration sans connexion" do
      get public_consignment_report_path(report.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Eline")
      expect(response.body).to include("Ajouter une vente")
      expect(response.body).to include("Commission des 4 Sources (20 %)")
      # Le builder par défaut pose sinon ses propres libellés, en anglais.
      expect(response.body).not_to include(">Label<")
      expect(response.body).not_to include(">Quantity<")
    end

    it "répond 404 sur un jeton inventé" do
      get public_consignment_report_path("pas-un-jeton")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("ne mène nulle part")
    end

    it "montre un état figé quand le relevé est vérifié" do
      report.update!(status: "verified", gross_cents: 3_150, commission_cents: 630, net_cents: 2_520)

      get public_consignment_report_path(report.token)

      expect(response.body).to include("est vérifié")
      expect(response.body).not_to include("Ajouter une vente")
    end
  end

  describe "PATCH /depot-vente/:token" do
    def declare(lines)
      patch public_consignment_report_path(report.token),
            params: { consignment_report: { consignment_report_lines_attributes: lines } }
    end

    it "enregistre les ventes et passe le relevé en déclaré" do
      expect {
        declare("0" => { label: "Savon", quantity: "3", unit_price_euros: "6,50" },
                "1" => { label: "Baume", quantity: "1", unit_price_euros: "12.00" })
      }.to change { report.consignment_report_lines.count }.by(2)

      expect(report.reload).to be_declared
      expect(report.declared_at).to be_present
      expect(report.live_gross_cents).to eq(3_150)
      expect(report.live_net_cents).to eq(2_520)
    end

    it "tolère la virgule comme séparateur décimal" do
      declare("0" => { label: "Savon", quantity: "2", unit_price_euros: "6,25" })

      expect(report.consignment_report_lines.first.unit_price_cents).to eq(625)
    end

    it "laisse corriger tant que rien n'est vérifié" do
      declare("0" => { label: "Savon", quantity: "3", unit_price_euros: "6,50" })
      ligne = report.reload.consignment_report_lines.first

      patch public_consignment_report_path(report.token),
            params: { consignment_report: { consignment_report_lines_attributes: {
              "0" => { id: ligne.id, label: "Savon de Marseille", quantity: "4", unit_price_euros: "6,50" }
            } } }

      expect(ligne.reload.quantity).to eq(4)
      expect(ligne.label).to eq("Savon de Marseille")
    end

    it "laisse retirer une ligne" do
      declare("0" => { label: "Savon", quantity: "3", unit_price_euros: "6,50" })
      ligne = report.reload.consignment_report_lines.first

      expect {
        patch public_consignment_report_path(report.token),
              params: { consignment_report: { consignment_report_lines_attributes: {
                "0" => { id: ligne.id, _destroy: "1" }
              } } }
      }.to change { report.reload.consignment_report_lines.count }.by(-1)
    end

    it "refuse de rouvrir un relevé vérifié" do
      report.update!(status: "verified")

      declare("0" => { label: "Savon", quantity: "3", unit_price_euros: "6,50" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(report.reload.consignment_report_lines).to be_empty
    end

    it "refuse une ligne sans libellé plutôt que de l'enregistrer vide" do
      declare("0" => { label: "", quantity: "3", unit_price_euros: "6,50" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(report.reload).to be_requested
    end
  end
end
