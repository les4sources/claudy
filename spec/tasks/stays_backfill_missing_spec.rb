require "rails_helper"
require "rake"

RSpec.describe "stays:backfill_missing", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("stays:backfill_missing")
  end

  def run_task
    task = Rake::Task["stays:backfill_missing"]
    task.reenable
    # La tâche imprime un rapport : on le silence pour garder la sortie de test propre.
    original = $stdout
    $stdout = StringIO.new
    task.invoke
  ensure
    $stdout = original
  end

  def build_booking(**attrs)
    Booking.create!({
      firstname: "Backfill",
      email: "backfill@example.com",
      from_date: Date.new(2026, 10, 1),
      to_date: Date.new(2026, 10, 3),
      adults: 1,
      status: "confirmed",
      price_cents: 15_000
    }.merge(attrs))
  end

  it "ne laisse aucun Booking sans Stay après exécution" do
    b1 = build_booking(email: "a@example.com")
    b2 = build_booking(email: "b@example.com", platform: "airbnb")

    run_task

    expect(b1.reload.stay).to be_present
    expect(b2.reload.stay).to be_present
    expect(b2.reload.stay.source).to eq("ota")
  end

  it "est idempotente : un second passage ne crée aucun Stay" do
    build_booking(email: "c@example.com")
    run_task
    count_after_first = Stay.count

    expect { run_task }.not_to change(Stay, :count)
    expect(Stay.count).to eq(count_after_first)
  end

  it "ne recrée pas de Stay pour un Booking déjà rattaché" do
    booking = build_booking(email: "d@example.com")
    existing = Stays::EnsureForBooking.call(booking)

    expect { run_task }.not_to change(Stay, :count)
    expect(booking.reload.stay).to eq(existing)
  end

  it "couvre aussi les Bookings soft-deleted" do
    booking = build_booking(email: "deleted@example.com")
    booking.soft_delete!(validate: false) # deleted_at posé, la ligne subsiste

    run_task

    expect(Booking.with_deleted { Booking.unscoped.find(booking.id).stay }).to be_present
  end
end
