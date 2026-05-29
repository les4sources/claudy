require "rails_helper"

RSpec.describe Reventilation::EmailMatchApplier, type: :service do
  let!(:catch_all) { Customer.create!(email: Customer::CATCH_ALL_EMAIL, first_name: "Client", customer_type: "individual") }
  let!(:stay) { Stay.create!(customer: catch_all, arrival_date: Date.today + 1, departure_date: Date.today + 2) }

  def row(**attrs)
    { stay_id: stay.id, email: "match@example.com" }.merge(attrs)
  end

  describe "#run (real)" do
    it "creates the customer and reassigns the stay off the catch-all" do
      report = described_class.new(rows: [row(first_name: "Jean", last_name: "Dupont")]).run

      expect(report.n_applied).to eq(1)
      expect(report.n_created_customers).to eq(1)
      created = Customer.find_by(email: "match@example.com")
      expect(stay.reload.customer_id).to eq(created.id)
      expect(created.first_name).to eq("Jean")
    end

    it "reuses an existing customer with that email (no duplicate)" do
      existing = Customer.create!(email: "match@example.com", customer_type: "individual")
      report = described_class.new(rows: [row]).run

      expect(report.n_created_customers).to eq(0)
      expect(report.n_applied).to eq(1)
      expect(stay.reload.customer_id).to eq(existing.id)
      expect(Customer.unscoped.where(email: "match@example.com").count).to eq(1)
    end

    it "derives organization type from a group name" do
      described_class.new(rows: [row(organization_name: "KAP", email: "kap@example.com")]).run
      expect(Customer.find_by(email: "kap@example.com").customer_type).to eq("organization")
    end
  end

  describe "idempotence & safety" do
    it "skips a stay that is no longer on the catch-all" do
      other = Customer.create!(email: "other@example.com", customer_type: "individual")
      stay.update!(customer: other)

      report = described_class.new(rows: [row]).run
      expect(report.n_skipped_not_catch_all).to eq(1)
      expect(report.n_applied).to eq(0)
      expect(stay.reload.customer_id).to eq(other.id) # inchangé
    end

    it "is idempotent across two runs" do
      described_class.new(rows: [row]).run
      second = described_class.new(rows: [row]).run
      expect(second.n_applied).to eq(0)
      expect(second.n_skipped_not_catch_all).to eq(1)
    end

    it "records an error and writes nothing for an invalid email" do
      report = described_class.new(rows: [row(email: "pas-un-email")]).run
      expect(report.n_errors).to eq(1)
      expect(report.n_applied).to eq(0)
      expect(stay.reload.customer_id).to eq(catch_all.id)
    end

    it "records an error for an unknown stay id" do
      report = described_class.new(rows: [{ stay_id: 0, email: "x@example.com" }]).run
      expect(report.n_errors).to eq(1)
    end
  end

  describe "dry run" do
    it "validates applicability but writes nothing" do
      report = described_class.new(rows: [row], dry_run: true).run
      expect(report.dry_run).to be(true)
      expect(Customer.unscoped.where(email: "match@example.com")).to be_empty
      expect(stay.reload.customer_id).to eq(catch_all.id)
    end
  end
end
