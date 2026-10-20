require "rails_helper"

# Michael, 2026-10-19 — Stripe n'expose pas le PDF de sa facture de frais, mais
# le total des frais du mois, oui. On prérempli le montant du justificatif ; le
# PDF reste à déposer.
RSpec.describe Stripe::PrefillFeeInvoices do
  let(:today) { Date.new(2026, 10, 19) }
  let(:claudy) { double("client claudy") }
  let(:tranche) { double("client tranche de vie") }
  let(:clients) { { "claudy" => claudy, "tranche_de_vie" => tranche } }

  before do
    allow(claudy).to receive(:fee_cents) { |from:, to:| from == Date.new(2026, 9, 1) ? 4_210 : 0 }
    allow(tranche).to receive(:fee_cents).and_return(0)
  end

  def run(apply: true, **options)
    described_class.new(today: today, apply: apply, clients: clients, since: Date.new(2026, 8, 1), **options).run!
  end

  it "pose les frais d'un mois terminé comme montant déclaré, en le disant relevé chez Stripe" do
    report = run

    invoice = StripeFeeInvoice.find_for("claudy", Date.new(2026, 9, 1))
    expect(invoice.declared_fee_cents).to eq(4_210)
    expect(invoice).to be_fetched_from_stripe
    expect(report[:results].map(&:action)).to eq([:filled])
  end

  it "n'écrit rien en dry-run" do
    report = run(apply: false)

    expect(StripeFeeInvoice.count).to eq(0)
    expect(report[:results].map(&:action)).to eq([:to_fill])
  end

  it "ne crée pas de justificatif pour un mois sans frais" do
    run
    expect(StripeFeeInvoice.find_for("claudy", Date.new(2026, 8, 1))).to be_nil
    expect(StripeFeeInvoice.for_account("tranche_de_vie")).to be_empty
  end

  it "n'interroge jamais le mois en cours" do
    run(until_month: Date.new(2026, 10, 1))
    expect(claudy).not_to have_received(:fee_cents).with(from: Date.new(2026, 10, 1), to: anything)
  end

  it "n'écrase jamais un montant déjà déclaré" do
    StripeFeeInvoice.create!(account_key: "claudy", period_month: Date.new(2026, 9, 1), declared_fee_cents: 4_000)

    run

    invoice = StripeFeeInvoice.find_for("claudy", Date.new(2026, 9, 1))
    expect(invoice.declared_fee_cents).to eq(4_000)
    expect(invoice).not_to be_fetched_from_stripe
    expect(claudy).not_to have_received(:fee_cents).with(from: Date.new(2026, 9, 1), to: anything)
  end

  it "remplit le montant d'un justificatif qui n'a que son PDF" do
    existing = StripeFeeInvoice.create!(account_key: "claudy", period_month: Date.new(2026, 9, 1))

    run

    expect(existing.reload.declared_fee_cents).to eq(4_210)
  end

  it "passe un compte sans clé en le disant" do
    allow(tranche).to receive(:fee_cents).and_raise(StripeService::MissingKey, "La clé Stripe du compte « Tranche de Vie » n'est pas configurée")

    report = run

    expect(report[:messages].join).to include("Tranche de Vie")
    expect(StripeFeeInvoice.find_for("claudy", Date.new(2026, 9, 1))).to be_present
  end

  describe "un montant saisi à la main" do
    it "ne se dit plus relevé chez Stripe" do
      run
      invoice = StripeFeeInvoice.find_for("claudy", Date.new(2026, 9, 1))

      invoice.update!(declared_fee: 43.10)

      expect(invoice.reload).not_to be_fetched_from_stripe
    end

    it "reste relevé quand on redépose le même montant" do
      run
      invoice = StripeFeeInvoice.find_for("claudy", Date.new(2026, 9, 1))

      invoice.update!(declared_fee: "42.10", reference: "INV-2026-09")

      expect(invoice.reload).to be_fetched_from_stripe
    end
  end

  describe Stripe::PrefillFeeInvoices::Client do
    it "additionne la commission des paiements et les frais facturés à part" do
      transactions = [double(type: "charge", fee: 29, net: 971), double(type: "refund", fee: 0, net: -500),
                      double(type: "stripe_fee", fee: 0, net: -1_500), double(type: "payout", fee: 0, net: -10_000)]
      list = double(auto_paging_each: transactions.each)
      allow(StripeService).to receive(:for).and_return(double(request_options: { api_key: "sk_test" }))
      allow(::Stripe::BalanceTransaction).to receive(:list).and_return(list)

      expect(described_class.new("claudy").fee_cents(from: Date.new(2026, 9, 1), to: Date.new(2026, 10, 1))).to eq(1_529)
    end
  end
end
