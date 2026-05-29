require "rails_helper"

RSpec.describe LegacyBookingMigration::Runner, type: :service do
  def booking(**attrs)
    Booking.create!({ firstname: "Guest", from_date: Date.today + 1, to_date: Date.today + 3,
                      adults: 1, status: "confirmed" }.merge(attrs))
  end

  describe "#run (real)" do
    it "creates one Stay + StayItem per legacy record" do
      booking(email: "a@example.com")
      booking(email: "b@example.com")

      report = described_class.new.run

      expect(report.n_bookings_seen).to eq(2)
      expect(report.n_stays_created).to eq(2)
      expect(Stay.unscoped.count).to eq(2)
      expect(StayItem.unscoped.count).to eq(2)
    end

    it "is idempotent: a second run creates nothing new (AC critique)" do
      booking(email: "idem@example.com")
      first = described_class.new.run
      expect(first.n_stays_created).to eq(1)

      second = described_class.new.run
      expect(second.n_stays_created).to eq(0)
      expect(second.n_already_migrated).to eq(1)
      expect(Stay.unscoped.count).to eq(1)
      expect(Customer.unscoped.count).to eq(1)
    end

    it "attributes the migration to whodunnit system:migration (AC-40)" do
      booking(email: "trace@example.com")
      described_class.new.run
      version = PaperTrail::Version.where(item_type: "Stay").last
      expect(version.whodunnit).to eq("system:migration")
    end
  end

  describe "dry run (AC-33)" do
    it "tallies counters but writes nothing" do
      booking(email: "dry@example.com")

      report = described_class.new(dry_run: true).run

      expect(report.dry_run).to be(true)
      expect(report.n_bookings_seen).to eq(1)
      expect(Stay.unscoped.count).to eq(0)
      expect(Customer.unscoped.count).to eq(0)
    end
  end

  describe "customer routing (AC-37/47/49)" do
    it "routes a record without an exploitable email to the catch-all customer" do
      booking(email: nil)
      booking(email: "   ")

      report = described_class.new.run

      expect(report.n_rattaches_fourretout).to eq(2)
      catch_all = Customer.unscoped.find_by(email: Customer::CATCH_ALL_EMAIL)
      expect(catch_all).to be_present
      expect(Stay.unscoped.joins(:customer).where(customers: { id: catch_all.id }).count).to eq(2)
    end

    it "gives a distinct OTA address its own customer (no fine dedup)" do
      booking(email: "guest-1@guest.airbnb.com")
      booking(email: "guest-2@guest.booking.com")

      described_class.new.run

      expect(Customer.unscoped.where.not(email: Customer::CATCH_ALL_EMAIL).count).to eq(2)
    end

    it "upserts a single customer for two bookings sharing an email" do
      booking(email: "repeat@example.com")
      booking(email: "REPEAT@example.com")

      report = described_class.new.run

      expect(Customer.unscoped.where(email: "repeat@example.com").count).to eq(1)
      expect(report.n_stays_created).to eq(2)
    end
  end

  describe "history coverage / ventilation" do
    it "categorizes the whole history (active, past, canceled, soft-deleted)" do
      booking(email: "future@example.com", to_date: Date.today + 10)
      booking(email: "past@example.com", from_date: Date.today - 10, to_date: Date.today - 5)
      booking(email: "cancel@example.com", status: "canceled")
      deleted = booking(email: "deleted@example.com")
      deleted.soft_delete!(validate: false)

      report = described_class.new.run

      expect(report.n_actifs).to eq(1)
      expect(report.n_passes).to eq(1)
      expect(report.n_annules).to eq(1)
      expect(report.n_soft_deleted).to eq(1)
      expect(report.n_stays_created).to eq(4)
    end
  end
end
