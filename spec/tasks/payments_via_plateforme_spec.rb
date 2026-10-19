require "rails_helper"
require "rake"

# « Via Airbnb ou Booking » (Michael 2026-10-18/19) : un séjour venu d'une de
# ces plateformes n'est payé ni par virement, ni en liquide, ni en ligne. La
# rake repasse les paiements de ces séjours sur ce moyen unique, sauf un vrai
# paiement Stripe et le miroir d'une Pizza Party Tranches de Vie.
RSpec.describe "payments:via_plateforme", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("payments:via_plateforme")
  end

  def run_task(apply: false)
    task = Rake::Task["payments:via_plateforme"]
    task.reenable
    previous_apply = ENV["APPLY"]
    ENV["APPLY"] = apply ? "1" : nil
    original = $stdout
    buffer = StringIO.new
    $stdout = buffer
    task.invoke
    buffer.string
  ensure
    $stdout = original
    ENV["APPLY"] = previous_apply
  end

  let(:customer) { Customer.create!(email: "guest@example.com", customer_type: "individual", first_name: "Roel") }
  let(:arrivee) { Date.today + 30 }

  def sejour(platform:, source: "manual")
    stay = Stay.create!(customer: customer, source: source, status: "confirmed",
                        arrival_date: arrivee, departure_date: arrivee + 2, total_amount_cents: 30_000)
    booking = Booking.create!(firstname: "Roel", adults: 2, from_date: arrivee, to_date: arrivee + 2, platform: platform)
    StayItem.create!(stay: stay, bookable: booking)
    stay
  end

  let!(:airbnb) { sejour(platform: "airbnb") }
  let!(:booking_com) { sejour(platform: "bookingdotcom") }
  let!(:direct) { sejour(platform: "web") }
  let!(:virement) { Payment.create!(stay: airbnb, amount_cents: 20_000, payment_method: "bank_transfer", status: "paid") }
  let!(:en_ligne) { Payment.create!(stay: airbnb, amount_cents: 10_000, payment_method: "stripe", status: "pending") }
  let!(:ancien_airbnb) { Payment.create!(stay: airbnb, amount_cents: 1_000, payment_method: "airbnb", status: "paid") }
  let!(:stripe_reel) do
    Payment.create!(stay: airbnb, amount_cents: 4_000, payment_method: "card", status: "paid", stripe_payment_intent_id: "pi_123")
  end
  let!(:chez_booking) { Payment.create!(stay: booking_com, amount_cents: 30_000, payment_method: "cash", status: "paid") }
  let!(:hors_plateforme) { Payment.create!(stay: direct, amount_cents: 30_000, payment_method: "bank_transfer", status: "paid") }

  it "reconnaît les séjours Airbnb et Booking.com, pas la réservation directe" do
    expect(Stay.ota).to contain_exactly(airbnb, booking_com)
    expect(direct.ota?).to be(false)
  end

  it "reconnaît aussi le canal ota et les clients fourre-tout des plateformes" do
    par_canal = Stay.create!(customer: customer, source: "ota", status: "confirmed",
                             arrival_date: arrivee, departure_date: arrivee + 1)
    fourre_tout = Customer.create!(email: Customer::OTA_CATCH_ALL_EMAILS["bookingdotcom"], customer_type: "individual")
    par_client = Stay.create!(customer: fourre_tout, source: "manual", status: "confirmed",
                              arrival_date: arrivee, departure_date: arrivee + 1)
    expect(Stay.ota).to include(par_canal, par_client)
  end

  it "en DRY-RUN, annonce le décompte sans rien écrire" do
    sortie = run_task
    expect(sortie).to include("À changer                    : 4", "Gardés (Stripe, Pizza Party) : 1")
    expect(virement.reload.payment_method).to eq("bank_transfer")
  end

  it "avec APPLY=1, passe les paiements des deux plateformes sur le même moyen, tracé, et rien d'autre" do
    run_task(apply: true)
    expect([virement, en_ligne, ancien_airbnb, chez_booking].map { |p| p.reload.payment_method }).to all(eq("ota"))
    expect(en_ligne.status).to eq("pending")
    expect(stripe_reel.reload.payment_method).to eq("card")
    expect(hors_plateforme.reload.payment_method).to eq("bank_transfer")
    expect(virement.versions.last.whodunnit).to eq("rake payments:via_plateforme")
  end

  it "est idempotente" do
    run_task(apply: true)
    expect(run_task(apply: true)).to include("Déjà au bon moyen            : 4", "À changer                    : 0")
  end
end
