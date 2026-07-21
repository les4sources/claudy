require "rails_helper"
require "rake"

# Epic #126, Phase 4 — rappel J-30 avant expiration d'un pack coworking avec
# crédits restants. On vérifie le CIBLAGE (fenêtre J-30, payé, crédits, client
# joignable) et l'IDEMPOTENCE (aucun doublon), plus les edge cases contractuels
# (pack remboursé = soft-delete → crédits gelés, client soft-deleté).
RSpec.describe "coworking:send_expiry_reminders", type: :task do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("coworking:send_expiry_reminders")
  end

  def run_task
    task = Rake::Task["coworking:send_expiry_reminders"]
    task.reenable
    original = $stdout
    $stdout = StringIO.new
    task.invoke
  ensure
    $stdout = original
  end

  # Pack payé qui expire dans `expires_in_days`. `paid: false` laisse le paiement
  # en attente ; `used` pose des réservations pour consommer des crédits.
  def build_pack(email:, days: 5, expires_in_days: 20, paid: true, used: 0)
    customer = Customer.create!(email: email, customer_type: "individual")
    pack = CoworkingPack.create!(customer: customer, days_total: days,
                                 payment_method: (paid ? "card" : "bank_transfer"),
                                 expires_at: (Date.current + expires_in_days).to_time)
    Payment.create!(coworking_pack: pack, amount_cents: pack.price_cents,
                    payment_method: pack.payment_method, status: (paid ? "paid" : "pending"))
    used.times do |i|
      d = next_weekday(Date.current + 1 + i)
      pack.coworking_reservations.create!(date: d, customer: customer)
    end
    pack
  end

  def next_weekday(from)
    d = from
    d += 1 until (1..5).cover?(d.wday)
    d
  end

  it "rappelle un pack payé qui expire dans la fenêtre J-30 avec des crédits" do
    pack = build_pack(email: "soon@example.com", expires_in_days: 20)

    expect { run_task }
      .to have_enqueued_mail(CoworkingMailer, :pack_expiring).exactly(1).times

    expect(pack.reload.expiry_reminder_sent_at).to be_present
  end

  it "ignore un pack qui expire au-delà de 30 jours" do
    pack = build_pack(email: "far@example.com", expires_in_days: 60)

    expect { run_task }.not_to have_enqueued_mail(CoworkingMailer, :pack_expiring)
    expect(pack.reload.expiry_reminder_sent_at).to be_nil
  end

  it "ignore un pack sans crédit restant (tout consommé)" do
    pack = build_pack(email: "empty@example.com", days: 1, expires_in_days: 20, used: 1)

    expect { run_task }.not_to have_enqueued_mail(CoworkingMailer, :pack_expiring)
    expect(pack.reload.expiry_reminder_sent_at).to be_nil
  end

  it "ignore un pack non payé (en attente)" do
    pack = build_pack(email: "unpaid@example.com", expires_in_days: 20, paid: false)

    expect { run_task }.not_to have_enqueued_mail(CoworkingMailer, :pack_expiring)
    expect(pack.reload.expiry_reminder_sent_at).to be_nil
  end

  it "edge case — pack remboursé à la main (soft-delete) : crédits gelés, aucun rappel" do
    pack = build_pack(email: "refunded@example.com", expires_in_days: 20)
    pack.soft_delete!(validate: false)

    expect { run_task }.not_to have_enqueued_mail(CoworkingMailer, :pack_expiring)
    expect(CoworkingPack.unscoped.find(pack.id).expiry_reminder_sent_at).to be_nil
  end

  it "edge case — client soft-deleté avec pack vivant : aucun rappel" do
    pack = build_pack(email: "gone@example.com", expires_in_days: 20)
    pack.customer.soft_delete!(validate: false)

    expect { run_task }.not_to have_enqueued_mail(CoworkingMailer, :pack_expiring)
    expect(pack.reload.expiry_reminder_sent_at).to be_nil
  end

  it "est idempotente : un second passage ne renvoie aucun rappel (anti-doublon)" do
    pack = build_pack(email: "once@example.com", expires_in_days: 20)

    run_task
    first_sent_at = pack.reload.expiry_reminder_sent_at
    expect(first_sent_at).to be_present

    expect { run_task }.not_to have_enqueued_mail(CoworkingMailer, :pack_expiring)
    expect(pack.reload.expiry_reminder_sent_at).to eq(first_sent_at)
  end
end
