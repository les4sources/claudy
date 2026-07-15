require "rails_helper"

RSpec.describe Customers::UpsertByEmail do
  describe "email exploitable" do
    it "crée un Customer portant l'email normalisé (lowercase)" do
      customer = described_class.call(
        email: "  Alice@Example.COM ",
        attrs: { first_name: "Alice", last_name: "Martin" }
      )

      expect(customer).to be_persisted
      expect(customer.email).to eq("alice@example.com")
      expect(customer.first_name).to eq("Alice")
    end

    it "réutilise le même Customer pour le même email (aucun doublon)" do
      first  = described_class.call(email: "bob@example.com", attrs: { first_name: "Bob" })
      second = described_class.call(email: "BOB@example.com", attrs: { first_name: "Bobby" })

      expect(second.id).to eq(first.id)
      expect(Customer.where(email: "bob@example.com").count).to eq(1)
    end

    it "réutilise un Customer vivant préexistant sans le muter" do
      existing = Customer.create!(email: "carol@example.com", first_name: "Carol",
                                  customer_type: "individual")

      customer = described_class.call(email: "carol@example.com", attrs: { first_name: "Autre" })

      expect(customer.id).to eq(existing.id)
      expect(customer.reload.first_name).to eq("Carol")
    end

    it "traite un relais OTA (format valide) comme un email exploitable" do
      customer = described_class.call(email: "guest-xyz@guest.airbnb.com")

      expect(customer).to be_persisted
      expect(customer.email).to eq("guest-xyz@guest.airbnb.com")
      expect(customer.catch_all?).to be(false)
    end
  end

  describe "email inexploitable (vide ou invalide)" do
    it "rattache un email vide au Customer fourre-tout" do
      customer = described_class.call(email: "")

      expect(customer.email).to eq(Customer::CATCH_ALL_EMAIL)
      expect(customer.catch_all?).to be(true)
    end

    it "rattache un email invalide au Customer fourre-tout" do
      customer = described_class.call(email: "pas-un-email")

      expect(customer.catch_all?).to be(true)
    end

    it "réutilise le même Customer fourre-tout (un seul créé)" do
      first  = described_class.call(email: nil)
      second = described_class.call(email: "   ")

      expect(second.id).to eq(first.id)
      expect(Customer.where(email: Customer::CATCH_ALL_EMAIL).count).to eq(1)
    end
  end
end
