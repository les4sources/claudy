require "rails_helper"
require "rake"

# Facturation des espaces → paiements (epic #26 / #55). La rake transforme les
# données de facturation d'un SpaceBooking (colonnes `*_amount_cents`,
# `payment_method`, `payment_status`) en Payment rattachés au Stay :
#   - `paid`    du montant REÇU (paid_amount, ou prix si statut "paid") ;
#   - `pending` du SOLDE restant dû (prix − reçu), sur séjour vivant seulement.
# La caution (`deposit_amount_cents`) n'est JAMAIS transformée.
RSpec.describe "space_bookings:billing_to_payments", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("space_bookings:billing_to_payments")
  end

  def run_task(apply: false)
    task = Rake::Task["space_bookings:billing_to_payments"]
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

  let(:customer) do
    Customer.create!(email: "billing@example.com", customer_type: "individual",
                     first_name: "Ada", last_name: "Lovelace")
  end

  let(:from) { Date.today + 30 }
  let(:to)   { Date.today + 31 }

  # Crée un séjour + un SpaceBooking rattaché, avec les données de facturation
  # voulues. Le total du séjour est aligné sur le prix de l'espace par défaut.
  def build_stay_with_space(total_cents: nil, status: "confirmed", **sb_attrs)
    price = sb_attrs[:price_cents].to_i
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: from, departure_date: to,
                        total_amount_cents: total_cents || price)
    sb = SpaceBooking.create!({
      firstname: "Ada", group_name: "Les Analytiques",
      from_date: from, to_date: to, status: status
    }.merge(sb_attrs))
    stay.stay_items.create!(bookable: sb)
    [stay, sb]
  end

  context "DRY-RUN (par défaut)" do
    it "n'écrit aucun Payment" do
      build_stay_with_space(price_cents: 12_000, paid_amount_cents: 5_000,
                            payment_method: "cash", payment_status: "partially_paid")

      expect { run_task(apply: false) }.not_to change(Payment, :count)
    end
  end

  context "APPLY — paiement partiel (partially_paid)" do
    it "crée un Payment paid du reçu ET un Payment pending du solde" do
      stay, sb = build_stay_with_space(price_cents: 12_000, paid_amount_cents: 5_000,
                                       payment_method: "cash", payment_status: "partially_paid")

      expect { run_task(apply: true) }.to change(Payment, :count).by(2)

      paid = Payment.find_by(space_booking_id: sb.id, status: "paid")
      pending = Payment.find_by(space_booking_id: sb.id, status: "pending")

      expect(paid.amount_cents).to eq(5_000)
      expect(paid.payment_method).to eq("cash")
      expect(paid.stay).to eq(stay)

      expect(pending.amount_cents).to eq(7_000) # 12 000 − 5 000
      expect(pending.payment_method).to eq("cash")
      expect(pending.stay).to eq(stay)

      # Le statut de paiement du séjour est recalculé (encaissé partiel).
      expect(stay.reload.payment_status).to eq("partially_paid")
      # Aucun total de séjour modifié.
      expect(stay.total_amount_cents).to eq(12_000)
    end
  end

  context "APPLY — payé en intégralité (paid) sans paid_amount renseigné" do
    it "crée un Payment paid du PRIX total, aucun pending, séjour soldé" do
      stay, sb = build_stay_with_space(price_cents: 12_000, paid_amount_cents: nil,
                                       payment_method: "bank_transfer", payment_status: "paid")

      expect { run_task(apply: true) }.to change(Payment, :count).by(1)

      paid = Payment.find_by(space_booking_id: sb.id, status: "paid")
      expect(paid.amount_cents).to eq(12_000)
      expect(paid.payment_method).to eq("bank_transfer")
      expect(Payment.exists?(space_booking_id: sb.id, status: "pending")).to be(false)
      expect(stay.reload.payment_status).to eq("paid")
    end
  end

  context "mapping du moyen de paiement" do
    it "conserve un moyen connu (bookingdotcom) à l'identique" do
      _stay, sb = build_stay_with_space(price_cents: 8_000, paid_amount_cents: 8_000,
                                        payment_method: "bookingdotcom", payment_status: "paid")

      run_task(apply: true)

      expect(Payment.find_by(space_booking_id: sb.id, status: "paid").payment_method).to eq("bookingdotcom")
    end

    it "ne crée rien et rapporte skipped_unknown_method pour un moyen inconnu" do
      _stay, sb = build_stay_with_space(price_cents: 8_000, paid_amount_cents: 8_000,
                                        payment_method: "paypal", payment_status: "paid")

      output = nil
      expect { output = run_task(apply: true) }.not_to change(Payment, :count)
      expect(output).to match(/moyen inconnu.*1/m)
      expect(output).to match(/SpaceBooking ##{sb.id}.*"paypal"/)
    end
  end

  context "caution (deposit)" do
    it "ne transforme JAMAIS la caution en paiement, mais la liste" do
      _stay, sb = build_stay_with_space(total_cents: 0, price_cents: 0,
                                        deposit_amount_cents: 30_000,
                                        payment_method: "bank_transfer", payment_status: "pending")

      output = nil
      expect { output = run_task(apply: true) }.not_to change(Payment, :count)
      expect(output).to match(/Cautions listées.*1/)
      expect(output).to match(/SpaceBooking ##{sb.id} : caution 300\.00 €/)
    end
  end

  context "séjour mort (declined/canceled) avec solde dû" do
    it "ne crée pas de pending et le rapporte en skipped_dead_status" do
      _stay, sb = build_stay_with_space(price_cents: 12_000, paid_amount_cents: 0,
                                        payment_method: "cash", payment_status: "pending",
                                        status: "canceled")

      output = nil
      expect { output = run_task(apply: true) }.not_to change(Payment, :count)
      expect(output).to match(/séjour mort.*#{sb.id}/)
    end
  end

  context "idempotence" do
    it "un second passage APPLY ne crée aucun Payment supplémentaire" do
      build_stay_with_space(price_cents: 12_000, paid_amount_cents: 5_000,
                            payment_method: "cash", payment_status: "partially_paid")

      run_task(apply: true)

      output = nil
      expect { output = run_task(apply: true) }.not_to change(Payment, :count)
      expect(output).to match(/Payment PAID créés\s+:\s+0/)
      expect(output).to match(/Payment PENDING créés\s+:\s+0/)
    end
  end
end
