require "rails_helper"

RSpec.describe PhoneNumber do
  it "normalise une saisie belge locale en E.164" do
    expect(described_class.normalize("0470 12 34 56")).to eq("+32470123456")
    expect(described_class.normalize("+32 (0)81 12 34 56")).to eq("+3281123456")
  end

  it "renvoie nil pour un numéro vide ou invalide" do
    expect(described_class.normalize("")).to be_nil
    expect(described_class.normalize("123")).to be_nil
  end

  describe "Human#phone" do
    it "stocke le numéro en E.164" do
      expect(Human.create!(name: "Ana", phone: "0470/12.34.56").phone).to eq("+32470123456")
    end

    it "refuse un numéro illisible" do
      human = Human.new(name: "Bob", phone: "pas un numéro")
      expect(human).not_to be_valid
      expect(human.errors[:phone]).to be_present
    end

    it "accepte l'absence de numéro" do
      expect(Human.new(name: "Cléo", phone: "")).to be_valid
    end
  end
end
