require "rails_helper"
require Rails.root.join("spec/support/revenue_share_builders")
require Rails.root.join("spec/support/finance_builders")

# Issue #247 — l'émission. Le moment où une proposition devient un document :
# montants figés, écriture passée, mail parti. Et rejouable sans dommage.
RSpec.describe RevenueShares::Issue do
  include RevenueShareBuilders
  include FinanceBuilders

  let(:lodging) { build_tiny_house }
  let(:agreement) { build_agreement(lodging) }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:charge) do
    build_general_account(code: GeneralAccount::REVENUE_SHARE_CODE,
                          name: "Reversements aux propriétaires", klass: 6, nature: "expense")
  end
  let!(:supplier) do
    build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability")
  end

  let(:statement) do
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 50_000)
    RevenueShares::Generate.new(agreement: agreement, period_from: Date.new(2026, 1, 1)).run!
  end

  it "fige les montants, passe l'écriture et envoie le mail" do
    expect { described_class.new(statement: statement).run! }
      .to change { ActionMailer::Base.deliveries.size }.by(1)

    statement.reload
    expect(statement.status).to eq("issued")
    expect(statement.issued_at).to be_present
    expect(statement.sent_at).to be_present
    expect(statement.posted_at).to be_present
    expect(statement.share_cents).to eq(25_000)

    entry = JournalEntry.find_by(source: statement, journal: "purchases")
    expect(entry).to be_present
    expect(entry.journal_lines.sum(:debit_cents)).to eq(25_000)
    expect(entry.journal_lines.sum(:credit_cents)).to eq(25_000)
    ligne_dette = entry.journal_lines.find { |l| l.credit_cents.positive? }
    expect(ligne_dette.general_account).to eq(supplier)
    expect(ligne_dette.third_party.name).to eq("Famille Dubois")
  end

  it "mémorise le tiers créé à la volée sur l'accord" do
    described_class.new(statement: statement).run!

    expect(agreement.reload.beneficiary_third_party).to be_present
    expect(agreement.beneficiary_third_party.kind).to eq("supplier")
  end

  it "est idempotente : ni seconde écriture, ni second mail" do
    described_class.new(statement: statement).run!

    expect { described_class.new(statement: statement).run! }
      .not_to change { ActionMailer::Base.deliveries.size }
    expect(JournalEntry.where(source: statement, journal: "purchases").count).to eq(1)
  end

  it "émet quand même sans email de bénéficiaire, et le dit en ne datant pas l'envoi" do
    agreement.update!(beneficiary_email: nil)

    expect { described_class.new(statement: statement).run! }
      .not_to change { ActionMailer::Base.deliveries.size }
    expect(statement.reload.status).to eq("issued")
    expect(statement.sent_at).to be_nil
  end

  it "refuse d'émettre sans le compte de reversement au référentiel" do
    charge.destroy
    expect { described_class.new(statement: statement).run! }
      .to raise_error(Accounting::PostRevenueShareStatement::MissingAccount)
    expect(statement.reload.status).to eq("draft")
  end
end
