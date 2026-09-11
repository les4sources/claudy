require "rails_helper"

# Epic #248, phase 2 — le tableau de bord mensuel du dépôt-vente.
RSpec.describe "Comptabilité > Dépôt-vente", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let!(:eline) do
    Consignor.create!(name: "Eline", email: "eline@example.com", settlement_mode: "invoice",
                      commission_percent: 20, starts_on: Date.new(2026, 1, 1))
  end
  let!(:bruno) do
    Consignor.create!(name: "Bruno", email: "bruno@example.com", settlement_mode: "transfer",
                      commission_percent: 20, iban: "BE68539007547034", starts_on: Date.new(2026, 1, 1))
  end
  let(:aout) { Date.new(2026, 8, 1) }

  before { sign_in user }

  describe "GET /finance/consignments" do
    it "dit qui a déclaré et qui reste muet" do
      declare = ConsignmentReport.create!(consignor: eline, period_month: aout, status: "declared",
                                          declared_at: Time.current)
      declare.consignment_report_lines.create!(label: "Savon", quantity: 3, unit_price_cents: 650)
      ConsignmentReport.create!(consignor: bruno, period_month: aout, requested_at: Time.current)

      get finance_consignment_reports_path(month: "2026-08")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Eline", "Bruno")
      expect(response.body).to include("Déclaré", "Demandé")
      expect(response.body).to include("subnav-accounting")
      # Le rappel de la commande doit rester lisible : Slim avale un `APPLY=1`
      # collé derrière une classe, il le prend pour un attribut.
      expect(response.body).to include("APPLY=1")
      # 19,50 € vendus, 3,90 € de commission, 15,60 € pour l'artisan.
      expect(response.body).to include("19,50")
      expect(response.body).to include("15,60")
    end

    # Sans ça, l'écran dirait « tout le monde a déclaré » alors que le rake n'a
    # simplement jamais été lancé.
    it "signale les artisans sans relevé pour le mois" do
      get finance_consignment_reports_path(month: "2026-08")

      expect(response.body).to include("artisan(s) sans relevé")
      expect(response.body).to include("Eline")
    end

    it "ne signale pas un artisan dont le contrat ne court pas ce mois-là" do
      eline.update!(ends_on: Date.new(2026, 6, 30))

      get finance_consignment_reports_path(month: "2026-08")

      expect(response.body).to include("Bruno")
      expect(response.body).not_to match(/sans relevé.*\n.*Eline/)
    end

    it "retombe sur le mois courant quand la date est illisible" do
      get finance_consignment_reports_path(month: "n'importe quoi")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.l(Date.current.beginning_of_month, format: "%B %Y"))
    end
  end

  describe "POST /finance/consignments/:id/resend" do
    let!(:report) { ConsignmentReport.create!(consignor: eline, period_month: aout) }

    # La suite tourne sous `queue_adapter: :inline` : `deliver_later` part pour
    # de vrai, et l'email atterrit dans `deliveries`.
    it "renvoie la demande et horodate" do
      expect {
        post resend_finance_consignment_report_path(report)
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(ActionMailer::Base.deliveries.last.to).to eq(["eline@example.com"])
      expect(report.reload.requested_at).to be_present
      expect(response).to redirect_to(finance_consignment_reports_path(month: "2026-08"))
    end

    it "refuse d'envoyer à un artisan sans adresse" do
      eline.update_column(:email, nil)

      post resend_finance_consignment_report_path(report)

      follow_redirect!
      expect(report.reload.requested_at).to be_nil
    end
  end
end
