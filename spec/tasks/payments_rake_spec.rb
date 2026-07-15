require "rails_helper"
require "rake"

# Epic #26, Phase 4 — verrouillage stay_id côté Payment.
RSpec.describe "payments rake tasks", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("payments:verify_stay_links")
  end

  # Invoque une tâche en silençant son rapport pour garder la sortie de test propre.
  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    original = $stdout
    $stdout = StringIO.new
    task.invoke
  ensure
    $stdout = original
  end

  def build_booking(email:)
    Booking.create!(firstname: "Verrou", email: email, from_date: Date.new(2026, 11, 1),
                    to_date: Date.new(2026, 11, 3), adults: 1, status: "confirmed", price_cents: 20_000)
  end

  # Un Payment LEGACY : booking rattaché à un Stay vivant, mais paiement sans
  # stay_id (état d'avant la Phase 4). On contourne la validation de présence.
  def legacy_stayless_payment(email:)
    booking = build_booking(email: email)
    Stays::EnsureForBooking.call(booking)
    payment = Payment.new(booking: booking, amount_cents: 10_000, status: "pending",
                          payment_method: "card")
    payment.save!(validate: false)
    payment
  end

  describe "payments:verify_stay_links" do
    it "réussit (aucun abort) quand tous les Payment portent un stay vivant" do
      booking = build_booking(email: "ok@example.com")
      stay = Stays::EnsureForBooking.call(booking)
      Payment.create!(booking: booking, stay: stay, amount_cents: 10_000,
                      status: "pending", payment_method: "card")

      expect { run_task("payments:verify_stay_links") }.not_to raise_error
    end

    it "réussit trivialement quand il n'y a aucun Payment" do
      expect(Payment.with_deleted { Payment.unscoped.count }).to eq(0)
      expect { run_task("payments:verify_stay_links") }.not_to raise_error
    end

    it "abort (SystemExit) dès qu'un Payment n'a pas de stay valide" do
      legacy_stayless_payment(email: "hole@example.com")

      expect { run_task("payments:verify_stay_links") }.to raise_error(SystemExit)
    end

    it "considère invalide un stay_id pointant vers un Stay soft-deleted" do
      booking = build_booking(email: "dead-stay@example.com")
      stay = Stays::EnsureForBooking.call(booking)
      payment = Payment.create!(booking: booking, stay: stay, amount_cents: 10_000,
                                status: "pending", payment_method: "card")
      stay.soft_delete!(validate: false)
      expect(payment.reload.stay).to be_nil # default scope masque le Stay mort

      expect { run_task("payments:verify_stay_links") }.to raise_error(SystemExit)
    end
  end

  describe "payments:backfill_stay_from_booking" do
    it "rattache un Payment legacy au Stay vivant de son booking" do
      payment = legacy_stayless_payment(email: "backfill@example.com")
      expected_stay = payment.booking.stay
      expect(expected_stay).to be_present

      run_task("payments:backfill_stay_from_booking")

      expect(payment.reload.stay).to eq(expected_stay)
    end

    it "est idempotent : un second passage ne relie ni ne modifie rien" do
      legacy_stayless_payment(email: "idem@example.com")

      run_task("payments:backfill_stay_from_booking")
      stay_ids_after_first = Payment.with_deleted { Payment.unscoped.pluck(:stay_id) }

      expect { run_task("payments:backfill_stay_from_booking") }
        .not_to change { Payment.with_deleted { Payment.unscoped.pluck(:stay_id) } }
      expect(stay_ids_after_first).to all(be_present)
    end

    it "rend verify_stay_links vert après coup" do
      legacy_stayless_payment(email: "chain@example.com")

      run_task("payments:backfill_stay_from_booking")

      expect { run_task("payments:verify_stay_links") }.not_to raise_error
    end
  end
end
