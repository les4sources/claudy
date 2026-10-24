require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Espace des partenaires, étape 2 (Michael, 2026-10-22) : un artisan payé en
# volontariat. Son net est un défraiement, pas un achat : 619105 sur la
# Fondation. Et un relevé déjà passé en achat se repasse.
RSpec.describe "Dépôt-vente — artisan en volontariat" do
  include FinanceBuilders
  include ActiveSupport::Testing::TimeHelpers

  # « Domaine d'Ahinvaux SRL » passe avant « Fondation » dans l'ordre alphabétique :
  # c'est elle qui prend les achats, comme en prod.
  let!(:srl) { build_legal_entity(name: "Domaine d'Ahinvaux SRL", form: "srl") }
  let!(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fy_srl) { build_fiscal_year(srl, year: 2026) }
  let!(:fy_fondation) { build_fiscal_year(fondation, year: 2026) }
  let!(:marchandises) { build_general_account(code: "600000", name: "Achats de marchandises", klass: 6, nature: "expense") }
  let!(:volontariat) { build_general_account(code: "619105", name: "Volontariat Pôle Prod-Transfo-Ventes", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:banque_compte) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
  let!(:inter_entites) { build_general_account(code: "416100", name: "Comptes courants inter-entités", klass: 4, nature: "asset") }
  let!(:banque) { build_cash_account(fondation, banque_compte, name: "Triodos", kind: "bank") }

  let!(:eline) do
    Consignor.create!(name: "Eline", email: "eline-vol@example.com", settlement_mode: "volunteering",
                      commission_percent: 20, iban: "BE68539007547034")
  end

  around { |example| travel_to(Date.new(2026, 10, 23)) { example.run } }

  def verified_report(consignor = eline)
    report = ConsignmentReport.create!(consignor: consignor, period_month: Date.new(2026, 10, 1),
                                       status: "declared", declared_at: Time.current)
    report.consignment_report_lines.create!(label: "Bougie", quantity: 5, unit_price_cents: 2_420, position: 0)
    Consignments::Verify.new(consignment_report: report.reload).run!
  end

  def charge_line(entry) = entry.journal_lines.find { |line| line.debit_cents.to_i.positive? }

  describe "la fiche de l'artisan" do
    it "se paie par virement, IBAN obligatoire" do
      expect(eline).to be_volunteering
      expect(eline).to be_paid_by_transfer
      expect(eline.settlement_mode_label).to eq("Volontariat (virement de la Fondation)")

      eline.iban = nil
      expect(eline).not_to be_valid
      expect(eline.errors[:iban].join).to include("virement")
    end
  end

  describe "le règlement" do
    it "passe la charge en 619105 sur la Fondation" do
      report = Consignments::Settle.new(consignment_report: verified_report).run!
      entry = report.journal_entry

      expect(entry.legal_entity).to eq(fondation)
      expect(charge_line(entry).general_account).to eq(volontariat)
      expect(charge_line(entry).debit_cents).to eq(9_680)
      expect(report.legal_entity).to eq(fondation)
      expect(report).to be_awaiting_transfer
    end

    it "garde l'achat de marchandises sur la SRL pour un artisan payé par virement" do
      eline.update!(settlement_mode: "transfer")
      report = Consignments::Settle.new(consignment_report: verified_report).run!

      expect(report.journal_entry.legal_entity).to eq(srl)
      expect(charge_line(report.journal_entry).general_account).to eq(marchandises)
    end
  end

  describe "repasser un relevé passé avant le changement de mode" do
    let!(:report) do
      eline.update!(settlement_mode: "transfer")
      Consignments::Settle.new(consignment_report: verified_report).run!.tap do
        eline.update!(settlement_mode: "volunteering")
      end
    end

    it "contre-passe l'achat sur la SRL et passe le volontariat sur la Fondation" do
      old_entry = report.journal_entry
      service = Consignments::Repost.new(consignment_report: report.reload)
      expect(service).to be_needed
      expect(service.target).to eq([fondation, "619105"])

      repasse = service.run!

      mirror = JournalEntry.find_by(reversal_of_id: old_entry.id)
      expect(mirror.legal_entity).to eq(srl)
      expect(mirror.journal_lines.sum(:credit_cents)).to eq(9_680)
      expect(old_entry.reload.source).to be_nil

      entry = repasse.journal_entry
      expect(entry).not_to eq(old_entry)
      expect(entry.legal_entity).to eq(fondation)
      expect(charge_line(entry).general_account).to eq(volontariat)
      expect(repasse.legal_entity).to eq(fondation)
      expect(repasse).to be_awaiting_transfer
      expect(repasse.remaining_cents).to eq(9_680)
      expect(Consignments::Repost.new(consignment_report: repasse)).not_to be_needed
    end

    it "laisse ensuite payer le relevé depuis la banque de la Fondation" do
      repasse = Consignments::Repost.new(consignment_report: report.reload).run!
      ligne = CashEntry.create!(cash_account: banque, entry_date: Date.new(2026, 10, 8), amount_cents: -9_680,
                                label: "Eline — #{repasse.reference}", communication: repasse.reference)

      Finance::RecordConsignmentReportPayment.new(cash_entry: ligne, consignment_report: repasse).run!

      allocation = ligne.reload.cash_allocations.sole
      expect(allocation.legal_entity).to eq(fondation)
      expect(allocation.general_account).to eq(fournisseurs)
      expect(repasse.reload).to be_settled
    end

    it "refuse quand un virement est déjà rapproché du relevé" do
      ligne = CashEntry.create!(cash_account: banque, entry_date: Date.new(2026, 10, 8), amount_cents: -9_680,
                                label: "Eline", communication: report.reference)
      Finance::RecordConsignmentReportPayment.new(cash_entry: ligne, consignment_report: report.reload).run!

      expect {
        Consignments::Repost.new(consignment_report: report.reload).run!
      }.to raise_error(Consignments::Repost::Refused)
    end

    it "refuse une écriture qui suit déjà le mode de l'artisan" do
      eline.update!(settlement_mode: "transfer")

      expect(Consignments::Repost.new(consignment_report: report.reload)).not_to be_needed
      expect {
        Consignments::Repost.new(consignment_report: report).run!
      }.to raise_error(Consignments::Repost::Refused, /suit déjà/)
    end
  end
end
