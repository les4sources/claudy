require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #248, phase 3 — vérifier, régler, constater.
#
# La phase 2 avait donné à l'artisan un moyen de déclarer. Ce qui manquait,
# c'était tout ce qui vient après : corriger une ligne fausse, figer les totaux
# pour pouvoir payer dessus, générer l'écriture, et savoir — sans le cocher —
# que l'argent est bien parti.
RSpec.describe "Dépôt-vente — vérification et règlement (epic #248, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:marchandises) { build_general_account(code: "600000", name: "Achats de marchandises", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:banque_compte) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
  let!(:banque) { build_cash_account(entity, banque_compte, name: "Triodos", kind: "bank") }

  let(:user) { User.create!(email: "compta-dv@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:eline) do
    Consignor.create!(name: "Eline", email: "eline-dv@example.com", settlement_mode: "transfer",
                      commission_percent: 20, iban: "BE68539007547034")
  end

  def report_for(consignor, lines: [["Bougie", 4, 1_200], ["Savon", 2, 800]], month: Date.new(2026, 8, 1))
    report = ConsignmentReport.create!(consignor: consignor, period_month: month, status: "declared",
                                       declared_at: Time.current)
    lines.each_with_index do |(label, qty, price), index|
      report.consignment_report_lines.create!(label: label, quantity: qty,
                                              unit_price_cents: price, position: index)
    end
    report.reload
  end

  describe "la fiche du relevé" do
    it "montre les lignes, les totaux vivants et le geste à faire" do
      report = report_for(eline)

      get finance_consignment_report_path(report)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bougie")
      expect(response.body).to include("Vérifier ce relevé")
      # 4 × 12 € + 2 × 8 € = 64 €, commission 20 % = 12,80 €, net 51,20 €
      expect(report.displayed_gross_cents).to eq(6_400)
      expect(report.displayed_net_cents).to eq(5_120)
    end

    it "laisse corriger une ligne tant que rien n'est figé, et le trace" do
      report = report_for(eline)
      ligne = report.consignment_report_lines.first

      expect {
        patch finance_consignment_report_path(report), params: {
          consignment_report: {
            consignment_report_lines_attributes: {
              "0" => { id: ligne.id, label: "Bougie parfumée", quantity: 3, unit_price: "12,00" }
            }
          }
        }
      }.to change { ligne.reload.versions.count }.by(1)

      expect(ligne.label).to eq("Bougie parfumée")
      expect(ligne.quantity).to eq(3)
      expect(report.reload.displayed_gross_cents).to eq(3 * 1_200 + 2 * 800)
    end

    it "refuse de corriger un relevé déjà vérifié" do
      report = report_for(eline)
      Consignments::Verify.new(consignment_report: report).run!
      ligne = report.consignment_report_lines.first

      patch finance_consignment_report_path(report), params: {
        consignment_report: {
          consignment_report_lines_attributes: { "0" => { id: ligne.id, label: "Trop tard" } }
        }
      }

      expect(response).to redirect_to(finance_consignment_report_path(report))
      expect(ligne.reload.label).to eq("Bougie")
    end
  end

  describe "la vérification" do
    it "fige les totaux ET le taux" do
      report = report_for(eline)

      post verify_finance_consignment_report_path(report)

      report.reload
      expect(report.status).to eq("verified")
      expect(report.gross_cents).to eq(6_400)
      expect(report.commission_cents).to eq(1_280)
      expect(report.net_cents).to eq(5_120)
      expect(report.commission_percent).to eq(20)
      expect(report.verified_by).to eq(user)
    end

    it "ne se laisse pas réécrire par un contrat renégocié après coup" do
      report = report_for(eline)
      post verify_finance_consignment_report_path(report)

      eline.update!(commission_percent: 35)

      expect(report.reload.displayed_net_cents).to eq(5_120)
      expect(report.applied_commission_percent).to eq(20)
    end

    it "refuse un relevé sans ligne" do
      vide = ConsignmentReport.create!(consignor: eline, period_month: Date.new(2026, 9, 1),
                                       status: "declared")

      post verify_finance_consignment_report_path(vide)

      expect(response).to redirect_to(finance_consignment_report_path(vide))
      expect(vide.reload.status).to eq("declared")
    end
  end

  describe "le mode virement" do
    let(:report) do
      r = report_for(eline)
      Consignments::Verify.new(consignment_report: r).run!
      r.reload
    end

    it "génère une écriture à deux lignes sur le NET" do
      post settle_finance_consignment_report_path(report)

      entry = report.reload.journal_entry
      expect(entry).to be_present
      expect(entry.journal).to eq("purchases")
      expect(entry.journal_lines.sum(&:debit_cents)).to eq(5_120)
      expect(entry.journal_lines.sum(&:credit_cents)).to eq(5_120)
      credit = entry.journal_lines.find { |l| l.credit_cents.to_i.positive? }
      expect(credit.general_account).to eq(fournisseurs)
      expect(credit.third_party&.name).to eq("Eline")
    end

    it "est idempotent : régler deux fois ne crée qu'une écriture" do
      post settle_finance_consignment_report_path(report)
      expect { post settle_finance_consignment_report_path(report) }
        .not_to change(JournalEntry, :count)
    end

    it "fait apparaître le relevé sur « À payer », avec l'IBAN de l'artisan" do
      post settle_finance_consignment_report_path(report)

      get finance_payables_path

      expect(response.body).to include("Eline")
      expect(response.body).to include(report.reference)
      expect(response.body).to include("BE68539007547034")
    end

    it "n'y apparaît pas tant que l'écriture n'est pas passée" do
      report

      get finance_payables_path

      expect(response.body).not_to include(report.reference)
    end

    it "passe en réglé au rapprochement, et redevient vérifié si on le défait" do
      post settle_finance_consignment_report_path(report)
      entry = build_cash_entry(banque, amount_cents: -5_120, entry_date: Date.new(2026, 9, 3),
                               label: "Virement Eline")
      entry.cash_allocations.create!(general_account: fournisseurs, legal_entity: entity,
                                     document: report, amount_cents: -5_120, label: "Dépôt-vente")

      expect(report.reload.status).to eq("settled")
      expect(report.settled_on).to eq(Date.new(2026, 9, 3))

      entry.cash_allocations.reload.each(&:destroy!)

      expect(report.reload.status).to eq("verified")
      expect(report.settled_on).to be_nil
    end
  end

  describe "le mode facture" do
    let!(:artisan) do
      Consignor.create!(name: "Atelier du Bocq", email: "atelier@example.com",
                        settlement_mode: "invoice", commission_percent: 20)
    end
    let!(:tiers) { ThirdParty.create!(name: "Atelier du Bocq", kind: "supplier") }
    let(:report) do
      artisan.update!(third_party: tiers)
      r = report_for(artisan)
      Consignments::Verify.new(consignment_report: r).run!
      r.reload
    end

    def facture(total_cents: 5_120)
      invoice = PurchaseInvoice.create!(legal_entity: entity, third_party: tiers,
                                        number: "F-#{rand(100_000)}", issued_on: Date.new(2026, 9, 1),
                                        total_cents: total_cents)
      invoice.purchase_invoice_lines.create!(general_account: marchandises, amount_cents: total_cents)
      invoice
    end

    it "refuse de générer une écriture : c'est la facture qui porte la dette" do
      post settle_finance_consignment_report_path(report)

      expect(response).to redirect_to(finance_consignment_report_path(report))
      expect(report.reload.journal_entry).to be_nil
    end

    it "n'apparaît jamais sur « À payer » : sa facture y est déjà" do
      report

      get finance_payables_path

      expect(response.body).not_to include(report.reference)
    end

    it "se lie à une facture d'achat du même tiers" do
      invoice = facture

      post link_invoice_finance_consignment_report_path(report, purchase_invoice_id: invoice.id)

      expect(report.reload.purchase_invoice).to eq(invoice)
      expect(report.status).to eq("verified")
    end

    it "se solde quand la facture liée est payée, et pas avant" do
      invoice = facture
      post link_invoice_finance_consignment_report_path(report, purchase_invoice_id: invoice.id)
      invoice.update!(status: "to_pay")

      entry = build_cash_entry(banque, amount_cents: -5_120, entry_date: Date.new(2026, 9, 5),
                              label: "Virement Atelier")
      entry.cash_allocations.create!(general_account: fournisseurs, legal_entity: entity,
                                     third_party: tiers, document: invoice,
                                     amount_cents: -5_120, label: "Paiement facture")

      expect(invoice.reload.status).to eq("paid")
      expect(report.reload.status).to eq("settled")
    end

    it "affiche l'écart entre le net et la facture, sans jamais le corriger" do
      invoice = facture(total_cents: 6_000)
      post link_invoice_finance_consignment_report_path(report, purchase_invoice_id: invoice.id)

      get finance_consignment_report_path(report)

      expect(response.body).to include("Écart de")
      expect(report.reload.net_cents).to eq(5_120)
      expect(invoice.reload.total_cents).to eq(6_000)
    end

    it "se détache sans effacer le relevé" do
      invoice = facture
      post link_invoice_finance_consignment_report_path(report, purchase_invoice_id: invoice.id)

      post unlink_invoice_finance_consignment_report_path(report)

      expect(report.reload.purchase_invoice).to be_nil
      expect(report.consignment_report_lines.count).to eq(2)
    end
  end

  describe "le récapitulatif annuel" do
    it "agrège par artisan et s'exporte en CSV" do
      r1 = report_for(eline, month: Date.new(2026, 7, 1))
      Consignments::Verify.new(consignment_report: r1).run!
      report_for(eline, month: Date.new(2026, 8, 1), lines: [["Bougie", 1, 1_000]])

      get yearly_finance_consignment_reports_path(year: 2026)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Eline")

      get yearly_finance_consignment_reports_path(year: 2026, format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      # 64,00 € en juillet + 10,00 € en août = 74,00 € bruts
      expect(response.body).to include("Eline")
      expect(response.body).to include("74,00")
    end
  end

  describe "rake accounting:verify_consignments" do
    it "ne signale rien sur un règlement complet" do
      report = report_for(eline)
      Consignments::Verify.new(consignment_report: report).run!
      Consignments::Settle.new(consignment_report: report.reload).run!
      entry = build_cash_entry(banque, amount_cents: -5_120, entry_date: Date.new(2026, 9, 3),
                              label: "Virement Eline")
      entry.cash_allocations.create!(general_account: fournisseurs, legal_entity: entity,
                                     document: report, amount_cents: -5_120, label: "Dépôt-vente")

      expect(report.reload.status).to eq("settled")
      expect(report.net_cents).to eq(report.gross_cents - report.commission_cents)
      expect(report.posted?).to be(true)
    end
  end
end
