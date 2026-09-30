require "rails_helper"

RSpec.describe MailIntake::InvoiceCandidates do
  subject(:candidates) do
    described_class.new(<<~TXT)
      Facture n° F-2026-0912 du 12.10.2026
      TVA BE 0769.799.225 — client BE0508977707
      Sous-total 1.234,56 EUR TVA 21% 259,26
      Total à payer : 1 493,82 € avant le 15 octobre 2026
      IBAN BE68 5390 0754 7034 — Total USD 84.12
    TXT
  end

  it "trouve les montants dans leurs écritures belges et anglaises, en centimes" do
    expect(candidates.amounts.map { |c| [c[:raw], c[:value]] })
      .to eq([["1.234,56", 123_456], ["259,26", 25_926], ["1 493,82", 149_382], ["84.12", 8_412]])
  end

  it "ne prend pas une date écrite avec des points pour un montant" do
    expect(candidates.amounts.map { |c| c[:raw] }).not_to include("12.10")
  end

  it "trouve les dates chiffrées et en toutes lettres" do
    expect(candidates.dates.map { |c| c[:value] }).to eq([Date.new(2026, 10, 12), Date.new(2026, 10, 15)])
  end

  it "trouve le numéro qui suit « Facture n° », sans le confondre avec une date" do
    expect(candidates.numbers.map { |c| c[:raw] }).to eq(["F-2026-0912"])
  end

  it "normalise TVA et IBAN pour les comparer à ce qu'on a en base" do
    expect(candidates.vat_numbers).to eq(%w[0769799225 0508977707])
    expect(candidates.ibans).to include("BE68539007547034")
    expect(described_class.normalize_vat("BEBE0508977707")).to eq("0508977707")
  end
end
