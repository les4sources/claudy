require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #248, phase 3 — le virement qui paie le relevé d'un artisan en mode
# virement. Ligne #12216 (Eline, octobre 2026) : la file proposait la
# suggestion de Jev (619105) et jamais le relevé, qui restait dû.
RSpec.describe Finance::RecordConsignmentReportPayment do
  include FinanceBuilders

  let!(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(fondation, year: 2026) }
  let!(:marchandises) { build_general_account(code: "600000", name: "Achats de marchandises", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:banque) { build_cash_account(fondation, build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset")) }

  let!(:eline) do
    Consignor.create!(name: "Eline", email: "eline-paiement@example.com", settlement_mode: "transfer",
                      commission_percent: 20, iban: "BE68539007547034")
  end

  let(:releve) do
    r = ConsignmentReport.create!(consignor: eline, period_month: Date.new(2026, 9, 1), status: "declared",
                                  declared_at: Time.current)
    r.consignment_report_lines.create!(label: "Bougie", quantity: 4, unit_price_cents: 1_200, position: 0)
    r.consignment_report_lines.create!(label: "Savon", quantity: 2, unit_price_cents: 800, position: 1)
    Consignments::Verify.new(consignment_report: r.reload).run!
    Consignments::Settle.new(consignment_report: r.reload).run!
  end

  def virement(amount_cents: -5_120, communication: nil, iban: nil)
    build_cash_entry(banque, amount_cents: amount_cents, entry_date: Date.new(2026, 10, 22),
                             label: "Eline Vanhamme").tap do |e|
      e.update!(communication: communication, counterparty_iban: iban)
    end
  end

  describe "la proposition (MatchConsignmentReports)" do
    it "reconnaît la référence du relevé dans la communication" do
      entry = virement(communication: "#{releve.reference} Ventes artisan 09/2026")

      match = Finance::MatchConsignmentReports.new.for_entry(entry).sole
      expect(match.report).to eq(releve)
      expect(match.due_cents).to eq(5_120)
      expect(match.confidence).to eq(98)
    end

    it "reconnaît l'IBAN du contrat de l'artisan" do
      releve
      entry = virement(amount_cents: -1_000, iban: "BE68 5390 0754 7034")

      expect(Finance::MatchConsignmentReports.new.for_entry(entry).sole.confidence).to eq(95)
    end

    it "ne propose rien tant que le relevé n'est pas réglé (pas d'écriture)" do
      r = ConsignmentReport.create!(consignor: eline, period_month: Date.new(2026, 8, 1), status: "verified", net_cents: 5_120)
      entry = virement(communication: r.reference)

      expect(Finance::MatchConsignmentReports.new.for_entry(entry)).to be_empty
    end

    it "ne propose rien sur une ligne entrante" do
      releve
      expect(Finance::MatchConsignmentReports.new.for_entry(virement(amount_cents: 5_120))).to be_empty
    end
  end

  it "affecte la ligne sur le 440000, avec le relevé en document et le tiers de son écriture" do
    entry = virement
    described_class.new(consignment_report: releve, cash_entry: entry).run!

    allocation = entry.reload.cash_allocations.sole
    tiers = releve.journal_entry.journal_lines.find { |l| l.credit_cents.positive? }.third_party
    expect(allocation).to have_attributes(general_account: fournisseurs, document: releve, third_party: tiers,
                                          legal_entity: fondation, amount_cents: -5_120)
  end

  it "fait passer le relevé « réglé » et comptabilise la ligne" do
    entry = virement
    described_class.new(consignment_report: releve, cash_entry: entry).run!

    expect(releve.reload).to be_settled
    expect(releve.settled_on).to eq(Date.new(2026, 10, 22))
    expect(entry.reload).to be_posted
  end

  it "prend l'entité de l'écriture du relevé quand une autre banque paie" do
    srl = build_legal_entity(name: "SRL Domaine d'Ahinvaux")
    build_fiscal_year(srl, year: 2026)
    build_general_account(code: GeneralAccount::INTER_ENTITY_CODE, name: "Compte courant inter-entités", klass: 4, nature: "liability")
    releve.update!(legal_entity: srl)
    releve.journal_entry.update_columns(legal_entity_id: srl.id)

    entry = virement
    described_class.new(consignment_report: releve.reload, cash_entry: entry).run!

    expect(entry.reload.cash_allocations.sole.legal_entity).to eq(srl)
    expect(releve.reload).to be_settled
  end

  it "refuse de surpayer le relevé" do
    expect { described_class.new(consignment_report: releve, cash_entry: virement(amount_cents: -9_000), amount_cents: 9_000).run! }
      .to raise_error(described_class::TooMuch)
  end

  it "refuse un relevé déjà soldé" do
    described_class.new(consignment_report: releve, cash_entry: virement).run!

    expect { described_class.new(consignment_report: releve.reload, cash_entry: virement).run! }
      .to raise_error(described_class::NotPayable)
  end
end
