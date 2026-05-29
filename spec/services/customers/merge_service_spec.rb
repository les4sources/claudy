require "rails_helper"

RSpec.describe Customers::MergeService, type: :service do
  def customer(email, **attrs)
    Customer.create!({ email: email, customer_type: "individual" }.merge(attrs))
  end

  describe "full merge (AC-15/16/17/18)" do
    let(:source) { customer("source@example.com", phone: "+32470111111") }
    let(:target) { customer("target@example.com") }

    before do
      Stay.create!(customer: source, arrival_date: Date.today + 1, departure_date: Date.today + 3)
      Stay.create!(customer: source, arrival_date: Date.today + 5, departure_date: Date.today + 7)
    end

    it "moves every stay to the target and soft-deletes the emptied source" do
      service = described_class.new(source: source, target: target)
      expect(service.run).to be_truthy

      expect(service.stays_moved).to eq(2)
      expect(target.stays.count).to eq(2)
      expect(Stay.where(customer_id: source.id)).to be_empty
      expect(Customer.find_by(id: source.id)).to be_nil # soft-deleted, out of default scope
      expect(Customer.unscoped.find(source.id).deleted_at).to be_present
    end

    it "fills only blank target attributes from the source (target wins, AC-18)" do
      target.update!(phone: nil)
      described_class.new(source: source, target: target).run
      expect(target.reload.phone).to eq("+32470111111")
    end

    it "keeps the target's own value when it is already set" do
      target.update!(phone: "+32470999999")
      described_class.new(source: source, target: target).run
      expect(target.reload.phone).to eq("+32470999999")
    end

    it "records the customer change on the moved stay via PaperTrail (AC-17)" do
      stay = source.stays.first
      described_class.new(source: source, target: target).run
      expect(stay.reload.versions.last.object_changes).to include("customer_id")
    end
  end

  describe "guards" do
    it "refuses to merge a customer into itself" do
      c = customer("self@example.com")
      service = described_class.new(source: c, target: c)
      expect(service.run).to be(false)
      expect(service.error_message).to be_present
    end
  end

  describe "partial re-ventilation from the catch-all (AC-50)" do
    let(:catch_all) { customer(Customer::CATCH_ALL_EMAIL, first_name: "Client") }
    let(:real) { customer("real@example.com") }

    it "moves only the selected stays and leaves the catch-all active" do
      keep = Stay.create!(customer: catch_all, arrival_date: Date.today + 1, departure_date: Date.today + 2)
      move = Stay.create!(customer: catch_all, arrival_date: Date.today + 4, departure_date: Date.today + 5)

      service = described_class.new(source: catch_all, target: real)
      expect(service.run(stay_ids: [move.id])).to be_truthy

      expect(service.stays_moved).to eq(1)
      expect(real.stays).to contain_exactly(move)
      expect(catch_all.stays.reload).to contain_exactly(keep)
      expect(Customer.find_by(id: catch_all.id)).to eq(catch_all) # still live
    end
  end
end
