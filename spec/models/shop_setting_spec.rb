require "rails_helper"

# Epic #359, phase 3 — les coordonnées bancaires des QR et les compteurs de
# feuilles.
# == Schema Information
#
# Table name: shop_settings
#
#  id                           :bigint           not null, primary key
#  beneficiary_name             :string
#  bic                          :string
#  bread_sheets_printed_count   :integer          default(0), not null
#  grocery_sheets_printed_count :integer          default(0), not null
#  iban                         :text
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
RSpec.describe ShopSetting, type: :model do
  it "n'a qu'une ligne" do
    expect(described_class.current).to eq(described_class.current)
    expect(described_class.count).to eq(1)
  end

  it "normalise l'IBAN et le BIC, et chiffre l'IBAN au repos" do
    settings = described_class.create!(iban: "be68 5390 0754 7034", bic: " gkccbebb ", beneficiary_name: " Fondation ")
    expect(settings).to have_attributes(iban: "BE68539007547034", bic: "GKCCBEBB", beneficiary_name: "Fondation")
    expect(settings.formatted_iban).to eq("BE68 5390 0754 7034")
    raw = described_class.connection.select_value("SELECT iban FROM shop_settings WHERE id = #{settings.id}")
    expect(raw).not_to include("BE68539007547034")
  end

  it "refuse un IBAN ou un BIC faux" do
    expect(described_class.new(iban: "BE00 1234")).not_to be_valid
    expect(described_class.new(bic: "12")).not_to be_valid
  end

  it "n'est configuré qu'avec un IBAN et un bénéficiaire" do
    expect(described_class.new(iban: "BE68539007547034")).not_to be_bank_configured
    expect(described_class.new(iban: "BE68539007547034", beneficiary_name: "Fondation")).to be_bank_configured
  end

  it "numérote les feuilles Épicerie et Boulangerie séparément" do
    settings = described_class.current
    expect([settings.next_sheet_number!(:grocery), settings.next_sheet_number!(:grocery)]).to eq([1, 2])
    expect(settings.next_sheet_number!(:bread)).to eq(1)
  end
end
