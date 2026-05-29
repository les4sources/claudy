require "rails_helper"

RSpec.describe Customer, type: :model do
  def build_customer(**attrs)
    Customer.new({ email: "alice@example.com", customer_type: "individual" }.merge(attrs))
  end

  describe "email normalization (AC-2/AC-3)" do
    it "trims and downcases the email before validation" do
      customer = build_customer(email: "  Alice@Example.COM  ")
      customer.valid?
      expect(customer.email).to eq("alice@example.com")
    end

    it "treats a blank email as nil" do
      customer = build_customer(email: "   ")
      customer.valid?
      expect(customer.email).to be_nil
      expect(customer).not_to be_valid
    end
  end

  describe "email uniqueness among live rows (AC-3)" do
    it "rejects a second live customer with the same email (case-insensitive)" do
      build_customer(email: "dup@example.com").save!
      dup = build_customer(email: "DUP@example.com")
      expect(dup).not_to be_valid
      expect(dup.errors[:email]).to be_present
    end

    it "allows reusing the email of a soft-deleted customer" do
      first = build_customer(email: "reuse@example.com")
      first.save!
      first.soft_delete!(validate: false)

      reused = build_customer(email: "reuse@example.com")
      expect(reused).to be_valid
    end
  end

  describe "validations" do
    it "requires a known customer_type" do
      expect(build_customer(customer_type: "alien")).not_to be_valid
    end

    it "requires a known language and defaults to fr" do
      expect(build_customer.tap(&:valid?).language).to eq("fr")
      expect(build_customer(language: "es")).not_to be_valid
    end

    it "requires organization_name when the customer is an organization" do
      org = build_customer(customer_type: "organization", organization_name: nil)
      expect(org).not_to be_valid
      org.organization_name = "Les 4 Sources"
      expect(org).to be_valid
    end
  end

  describe ".exploitable_email? (AC-49)" do
    it "is false for blank or format-invalid addresses" do
      expect(Customer.exploitable_email?(nil)).to be(false)
      expect(Customer.exploitable_email?("  ")).to be(false)
      expect(Customer.exploitable_email?("not-an-email")).to be(false)
    end

    it "is true for a real address, including an OTA relay" do
      expect(Customer.exploitable_email?("bob@example.com")).to be(true)
      expect(Customer.exploitable_email?("guest-123@guest.airbnb.com")).to be(true)
    end
  end

  describe "#catch_all? (AC-47)" do
    it "is true only for the conventional catch-all email" do
      catch_all = build_customer(email: Customer::CATCH_ALL_EMAIL)
      expect(catch_all.catch_all?).to be(true)
      expect(build_customer(email: "someone@example.com").catch_all?).to be(false)
    end
  end

  describe "#name" do
    it "uses the organization name for organizations" do
      org = build_customer(customer_type: "organization", organization_name: "ACME")
      expect(org.name).to eq("ACME")
    end

    it "joins first and last name for individuals" do
      expect(build_customer(first_name: "Alice", last_name: "Martin").name).to eq("Alice Martin")
    end

    it "falls back to the email when no name is present" do
      expect(build_customer(email: "fallback@example.com").name).to eq("fallback@example.com")
    end
  end

  describe ".search" do
    it "matches on email, name and organization, case-insensitively" do
      a = build_customer(email: "search-alice@example.com", first_name: "Alice").tap(&:save!)
      b = build_customer(email: "other@example.com", customer_type: "organization",
                         organization_name: "Searchable Org").tap(&:save!)

      expect(Customer.search("ALICE")).to include(a)
      expect(Customer.search("searchable")).to include(b)
      expect(Customer.search("alice")).not_to include(b)
    end
  end
end
