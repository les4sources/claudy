require "rails_helper"

RSpec.describe Reservations::PhoneFormat do
  it "accepte un champ vide (facultatif)" do
    expect(described_class.valid?("")).to be(true)
    expect(described_class.valid?(nil)).to be(true)
  end

  it "accepte les formats usuels" do
    ["+32 470 12 34 56", "0470/12.34.56", "+33 6 12 34 56 78", "(081) 22 33 44"].each do |n|
      expect(described_class.valid?(n)).to be(true), n
    end
  end

  it "refuse les lettres et les longueurs impossibles" do
    ["appelez-moi", "12345", "+32 470 12 34 56 78 90 12"].each do |n|
      expect(described_class.valid?(n)).to be(false), n
    end
  end
end
