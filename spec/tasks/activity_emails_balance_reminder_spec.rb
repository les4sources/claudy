require "rails_helper"
require "rake"

# Epic #55, Phase 5 — relance du solde exigible à J-14 (sans blocage).
# On vérifie le CIBLAGE (J-14 + solde impayé, hors soldés/annulés) et
# l'IDEMPOTENCE (pas de second envoi).
RSpec.describe "activity_emails:balance_reminder", type: :task do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("activity_emails:balance_reminder")
  end

  def run_task
    task = Rake::Task["activity_emails:balance_reminder"]
    task.reenable
    # La tâche imprime un rapport : on le silence pour garder la sortie propre.
    original = $stdout
    $stdout = StringIO.new
    task.invoke
  ensure
    $stdout = original
  end

  # Un séjour minimal (sans bookables) suffit : `payable_amount_cents` dérive
  # de `total_amount_cents` moins les activités pending, et l'exigible impayé
  # se pilote donc via le total et les paiements encaissés.
  def build_stay(email:, arrival_offset:, total_cents: 40_000, paid_cents: 0, status: "pending")
    customer = Customer.create!(email: email, customer_type: "individual")
    stay = Stay.create!(customer: customer, status: status, total_amount_cents: total_cents,
                        arrival_date: Date.today + arrival_offset,
                        departure_date: Date.today + arrival_offset + 2)
    if paid_cents.positive?
      Payment.create!(stay: stay, amount_cents: paid_cents, status: "paid", payment_method: "card")
    end
    stay
  end

  it "relance les séjours à J-14 avec un solde exigible impayé" do
    stay = build_stay(email: "due@example.com", arrival_offset: 14)

    expect { run_task }
      .to have_enqueued_mail(StayBalanceReminderMailer, :reminder).exactly(1).times

    expect(stay.reload.balance_reminder_sent_at).to be_present
  end

  it "ignore les séjours hors fenêtre J-14 (arrivée dans ~30 jours)" do
    stay = build_stay(email: "far@example.com", arrival_offset: 30)

    expect { run_task }.not_to have_enqueued_mail(StayBalanceReminderMailer, :reminder)
    expect(stay.reload.balance_reminder_sent_at).to be_nil
  end

  it "ignore les séjours déjà soldés (aucun solde exigible)" do
    stay = build_stay(email: "paid@example.com", arrival_offset: 14, paid_cents: 40_000)

    expect { run_task }.not_to have_enqueued_mail(StayBalanceReminderMailer, :reminder)
    expect(stay.reload.balance_reminder_sent_at).to be_nil
  end

  it "ignore les séjours annulés même avec un solde" do
    stay = build_stay(email: "cancel@example.com", arrival_offset: 14, status: "cancelled")

    expect { run_task }.not_to have_enqueued_mail(StayBalanceReminderMailer, :reminder)
    expect(stay.reload.balance_reminder_sent_at).to be_nil
  end

  it "est idempotente : un second passage ne renvoie pas la relance" do
    stay = build_stay(email: "once@example.com", arrival_offset: 14)

    run_task
    first_sent_at = stay.reload.balance_reminder_sent_at
    expect(first_sent_at).to be_present

    expect { run_task }.not_to have_enqueued_mail(StayBalanceReminderMailer, :reminder)
    expect(stay.reload.balance_reminder_sent_at).to eq(first_sent_at)
  end
end
