require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 4 — l'artisan voit ce qu'il a reçu en face de ce qu'il a
# déclaré. Ses virements, et seulement les siens ; jamais le nom du client.
RSpec.describe "Portail — mes virements (epic #359, phase 4)", type: :request do
  include ActiveJob::TestHelper
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:eline) do
    Consignor.create!(name: "Eline", settlement_mode: "invoice", commission_percent: 20,
                      email: "eline@example.com", portal_enabled: true)
  end
  let!(:bruno) do
    Consignor.create!(name: "Bruno", settlement_mode: "invoice", email: "bruno@example.com", portal_enabled: true)
  end

  def sign_in_consignor(email)
    perform_enqueued_jobs { post portal_code_path, params: { email: email, context: "consignor" } }
    code = ActionMailer::Base.deliveries.last.body.encoded[/\b\d{6}\b/]
    post portal_login_path, params: { email: email, code: code }
  end

  def transfer(consignor, cents, communication, date: Date.current)
    build_cash_entry(bank, amount_cents: cents, entry_date: date).tap do |e|
      e.update!(consignor: consignor, communication: communication, counterparty_name: "MARTIN CLAIRE")
    end
  end

  before { ActionMailer::Base.deliveries.clear }

  it "exige la session artisan" do
    get portal_consignor_transfers_path

    expect(response).to redirect_to(portal_path(context: "consignor"))
  end

  context "Eline connectée" do
    before do
      transfer(eline, 1_250, "ARTISANAT ELINE")
      transfer(bruno, 9_900, "ARTISANAT BRUNO")
      sign_in_consignor("eline@example.com")
    end

    it "liste ses virements — date, communication, montant — et pas ceux de Bruno" do
      get portal_consignor_transfers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ARTISANAT ELINE", "12,50")
      expect(response.body).not_to include("ARTISANAT BRUNO")
      expect(response.body).not_to include("99,00")
      expect(response.body).not_to include("MARTIN CLAIRE")
    end

    it "le tableau de bord mène à ses virements et confronte le mois à la banque" do
      report = eline.consignment_reports.create!(period_month: Date.current.beginning_of_month, status: "declared")
      report.consignment_report_lines.create!(label: "Savon", quantity: 3, unit_price_cents: 500, payment_method: "qr")
      report.consignment_report_lines.create!(label: "Bougie", quantity: 1, unit_price_cents: 200, payment_method: "cash")

      get portal_consignments_path

      expect(response.body).to include(portal_consignor_transfers_path)
      expect(response.body).to include("Reçu en banque", "12,50", "Espèces déclarées", "2,00", "Écart", "2,50")
    end

    it "la page d'encodage du mois montre aussi la banque" do
      eline.consignment_reports.create!(period_month: Date.current.beginning_of_month, status: "declared")
        .consignment_report_lines.create!(label: "Savon", quantity: 1, unit_price_cents: 1_250, payment_method: "qr")

      get portal_consignor_report_path(period: Date.current.strftime("%Y-%m"))

      expect(response.body).to include("Face à la banque", "Reçu en banque")
    end
  end
end
