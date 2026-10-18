require "rails_helper"

# Apporteur d'un séjour (Michael, 2026-10-18) — liste fermée `Stay::REFERRALS`.
RSpec.describe Stay, "apporteur" do
  let(:customer) { Customer.create!(email: "apporteur@example.com", first_name: "A", last_name: "B") }

  describe ".referral_key" do
    it "reconnaît une clé connue, sans égard à la casse ni aux espaces" do
      expect(Stay.referral_key("semisto")).to eq("semisto")
      expect(Stay.referral_key(" SEMISTO ")).to eq("semisto")
    end

    it "renvoie nil pour une clé inconnue ou vide" do
      expect(Stay.referral_key("autre")).to be_nil
      expect(Stay.referral_key("")).to be_nil
      expect(Stay.referral_key(nil)).to be_nil
    end
  end

  it "accepte un apporteur connu et l'absence d'apporteur" do
    expect(Stay.new(customer: customer, referral: "semisto")).to be_valid
    expect(Stay.new(customer: customer, referral: nil)).to be_valid
  end

  it "refuse un apporteur hors liste" do
    stay = Stay.new(customer: customer, referral: "inconnu")
    expect(stay).not_to be_valid
    expect(stay.errors[:referral]).to include("Apporteur inconnu")
  end

  it "donne le nom de l'apporteur" do
    expect(Stay.new(referral: "semisto").referral_label).to eq("Semisto")
    expect(Stay.new.referral_label).to be_nil
  end
end
