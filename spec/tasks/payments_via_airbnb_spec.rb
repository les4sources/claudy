require "rails_helper"
require "rake"

# « Via Airbnb » (Michael 2026-10-18) : un séjour Airbnb n'est payé ni par
# virement, ni en liquide, ni en ligne. La rake repasse les paiements de ces
# séjours sur le bon moyen, sauf un vrai paiement Stripe et le miroir d'une
# Pizza Party Tranches de Vie.
RSpec.describe "payments:via_airbnb", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("payments:via_airbnb")
  end

  def run_task(apply: false)
    task = Rake::Task["payments:via_airbnb"]
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

  def sejour(platform:)
    stay = Stay.create!(customer: customer, source: "ota", status: "confirmed",
                        arrival_date: arrivee, departure_date: arrivee + 2, total_amount_cents: 30_000)
    booking = Booking.create!(firstname: "Roel", adults: 2, from_date: arrivee, to_date: arrivee + 2, platform: platform)
    StayItem.create!(stay: stay, bookable: booking)
    stay
  end

  let!(:airbnb) { sejour(platform: "airbnb") }
  let!(:booking_com) { sejour(platform: "bookingdotcom") }
  let!(:virement) { Payment.create!(stay: airbnb, amount_cents: 20_000, payment_method: "bank_transfer", status: "paid") }
  let!(:en_ligne) { Payment.create!(stay: airbnb, amount_cents: 10_000, payment_method: "stripe", status: "pending") }
  let!(:stripe_reel) do
    Payment.create!(stay: airbnb, amount_cents: 4_000, payment_method: "card", status: "paid", stripe_payment_intent_id: "pi_123")
  end
  let!(:ailleurs) { Payment.create!(stay: booking_com, amount_cents: 30_000, payment_method: "bank_transfer", status: "paid") }

  it "reconnaît le séjour Airbnb, pas celui de Booking.com" do
    expect(airbnb.airbnb?).to be(true)
    expect(booking_com.airbnb?).to be(false)
    expect(Stay.airbnb).to contain_exactly(airbnb)
  end

  it "reconnaît aussi un séjour du client fourre-tout Airbnb" do
    fourre_tout = Customer.create!(email: Customer::OTA_CATCH_ALL_EMAILS["airbnb"], customer_type: "individual")
    stay = Stay.create!(customer: fourre_tout, source: "ota", status: "confirmed",
                        arrival_date: arrivee, departure_date: arrivee + 1)
    expect(stay.airbnb?).to be(true)
    expect(Stay.airbnb).to include(stay)
  end

  it "en DRY-RUN, annonce le décompte sans rien écrire" do
    sortie = run_task
    expect(sortie).to include("À passer en « Via Airbnb »   : 2", "Gardés (Stripe, Pizza Party) : 1")
    expect(virement.reload.payment_method).to eq("bank_transfer")
  end

  it "avec APPLY=1, passe les paiements du séjour Airbnb en « Via Airbnb », tracé, et rien d'autre" do
    run_task(apply: true)
    expect(virement.reload.payment_method).to eq("airbnb")
    expect(en_ligne.reload.payment_method).to eq("airbnb")
    expect(en_ligne.status).to eq("pending")
    expect(stripe_reel.reload.payment_method).to eq("card")
    expect(ailleurs.reload.payment_method).to eq("bank_transfer")
    expect(virement.versions.last.whodunnit).to eq("rake payments:via_airbnb")
  end

  it "est idempotente" do
    run_task(apply: true)
    expect(run_task(apply: true)).to include("Déjà « Via Airbnb »          : 2", "À passer en « Via Airbnb »   : 0")
  end
end
