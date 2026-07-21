require "rails_helper"

# Epic #126, Phase 3 — coworking dans le portail client : achat de packs,
# réservation et annulation de journées, en self-service.
RSpec.describe "Portail client — Coworking", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before do
    ActionMailer::Base.deliveries.clear
    allow(StripeService.instance).to receive(:create_checkout_session)
      .and_return(OpenStruct.new(url: "https://checkout.stripe.test/session/abc"))
  end

  # Un lundi bien dans le futur, stable (pas de week-end, pas de « jour passé »).
  let(:day) { next_weekday(Date.current + 30) }

  def next_weekday(from)
    d = from
    d += 1 until (1..5).cover?(d.wday)
    d
  end

  def sign_in_coworking(email)
    perform_enqueued_jobs { post portal_code_path, params: { email: email, context: "coworking" } }
    code = ActionMailer::Base.deliveries.last.body.encoded[/\b\d{6}\b/]
    post portal_login_path, params: { email: email, code: code }
    Customer.find_by(email: email)
  end

  def paid_pack(customer, days: 5, expires_at: nil)
    pack = CoworkingPack.create!(customer: customer, days_total: days,
                                 payment_method: "card", expires_at: expires_at)
    Payment.create!(coworking_pack: pack, amount_cents: pack.price_cents,
                    payment_method: "card", status: "paid")
    pack
  end

  def pending_pack(customer, days: 5)
    pack = CoworkingPack.create!(customer: customer, days_total: days, payment_method: "bank_transfer")
    Payment.create!(coworking_pack: pack, amount_cents: pack.price_cents,
                    payment_method: "bank_transfer", status: "pending")
    pack
  end

  # Remplit `n` bureaux d'un jour avec des réservations d'AUTRES clients.
  def fill_day(date, n)
    n.times do |i|
      c = Customer.create!(first_name: "Occupant#{i}", email: "occ#{i}-#{date}@example.com")
      paid_pack(c, days: 1).coworking_reservations.create!(date: date, customer: c)
    end
  end

  describe "accès" do
    it "redirige un visiteur non connecté vers la connexion contexte coworking" do
      get portal_coworking_path
      expect(response).to redirect_to(portal_path(context: "coworking"))
    end
  end

  describe "achat de pack (Stripe stubbé)" do
    it "crée un pack + un Payment en attente ancré, et redirige vers Stripe" do
      sign_in_coworking("neo@example.com")

      expect {
        post portal_coworking_purchase_path, params: { days_total: 5 }
      }.to change(CoworkingPack, :count).by(1)

      pack = CoworkingPack.last
      payment = pack.payments.first
      expect(payment.status).to eq("pending")
      expect(payment.amount_cents).to eq(8_000)
      expect(payment.stay_id).to be_nil
      expect(pack.payment_status).to eq("pending")
      expect(response).to redirect_to("https://checkout.stripe.test/session/abc")
    end

    it "le webhook checkout.session.completed marque le pack payé et ouvre les crédits" do
      sign_in_coworking("neo@example.com")
      post portal_coworking_purchase_path, params: { days_total: 10 }
      pack = CoworkingPack.last
      payment = pack.payments.first

      Stripe::CompletedCheckoutService.new(payment: payment).run!(
        stripe_checkout_session_id: "cs_1", stripe_payment_intent_id: "pi_1"
      )

      expect(payment.reload.status).to eq("paid")
      expect(pack.reload.paid?).to be true
      expect(pack.days_remaining).to eq(10)
    end

    it "envoie l'email de confirmation d'achat au passage payé" do
      sign_in_coworking("neo@example.com")
      post portal_coworking_purchase_path, params: { days_total: 1 }
      payment = CoworkingPack.last.payments.first

      expect {
        perform_enqueued_jobs do
          Stripe::CompletedCheckoutService.new(payment: payment).run!(
            stripe_checkout_session_id: "cs_2", stripe_payment_intent_id: "pi_2"
          )
        end
      }.to change { ActionMailer::Base.deliveries.count }.by_at_least(1)

      mail = ActionMailer::Base.deliveries.find { |m| m.subject.include?("pack de coworking") }
      expect(mail).to be_present
      expect(mail.to).to eq(["neo@example.com"])
    end
  end

  describe "achat sans compte (auto-création client)" do
    it "crée un Customer individual à la connexion coworking" do
      expect { sign_in_coworking("prospect@example.com") }.to change(Customer, :count).by(1)
      customer = Customer.find_by(email: "prospect@example.com")
      expect(customer.customer_type).to eq("individual")
    end
  end

  describe "réservation d'une journée" do
    it "consomme 1 crédit du pack qui expire le plus tôt (FIFO expiration)" do
      customer = sign_in_coworking("ana@example.com")
      soon  = paid_pack(customer, days: 1, expires_at: (day + 5))
      later = paid_pack(customer, days: 1, expires_at: (day + 200))

      post portal_coworking_reservations_path, params: { date: day.iso8601 }

      expect(soon.reload.days_remaining).to eq(0)
      expect(later.reload.days_remaining).to eq(1)
    end

    it "refuse un jour déjà complet (3/3) sans consommer de crédit" do
      customer = sign_in_coworking("ana@example.com")
      pack = paid_pack(customer, days: 5)
      fill_day(day, 3)

      post portal_coworking_reservations_path, params: { date: day.iso8601 }

      expect(pack.reload.days_used).to eq(0)
      follow_redirect!
      expect(response.body).to include("complet")
    end

    it "refuse quand le pack est en attente de paiement" do
      customer = sign_in_coworking("ana@example.com")
      pending_pack(customer)

      post portal_coworking_reservations_path, params: { date: day.iso8601 }

      expect(CoworkingReservation.count).to eq(0)
      follow_redirect!
      expect(response.body).to include("attente de paiement")
    end

    it "ne réserve pas sur un crédit expiré" do
      customer = sign_in_coworking("ana@example.com")
      paid_pack(customer, days: 5, expires_at: (day - 1)) # expiré à la date visée

      post portal_coworking_reservations_path, params: { date: day.iso8601 }

      expect(CoworkingReservation.count).to eq(0)
    end

    it "ne réserve pas sur un pack soft-deleté" do
      customer = sign_in_coworking("ana@example.com")
      pack = paid_pack(customer, days: 5)
      pack.soft_delete!(validate: false)

      post portal_coworking_reservations_path, params: { date: day.iso8601 }

      expect(CoworkingReservation.count).to eq(0)
    end
  end

  describe "concurrence — jamais plus de 3 réservations vivantes par jour" do
    it "refuse la 4e réservation du jour (verrou + revérification sous transaction)" do
      fill_day(day, 2)
      a = Customer.create!(first_name: "A", email: "conc-a@example.com")
      b = Customer.create!(first_name: "B", email: "conc-b@example.com")
      paid_pack(a, days: 1)
      paid_pack(b, days: 1)

      expect(Coworking::ReserveDay.new(customer: a, date: day).run).to be(true)  # 3e
      expect(Coworking::ReserveDay.new(customer: b, date: day).run).to be(false) # 4e refusée

      expect(CoworkingReservation.count_on(day)).to eq(3)
    end
  end

  describe "annulation (fenêtre 08:00 Europe/Brussels)" do
    def at_brussels(date, hour)
      Time.use_zone("Europe/Brussels") { Time.zone.local(date.year, date.month, date.day, hour, 0, 0) }
    end

    # Tout se joue à l'intérieur du temps figé : la session portail (cookie 24h)
    # doit être fraîche RELATIVEMENT au voyage temporel.
    it "annule avant 8h le jour même et libère le crédit (re-réservable)" do
      travel_to at_brussels(day, 7) do
        customer = sign_in_coworking("ana@example.com")
        pack = paid_pack(customer, days: 1)
        res = pack.coworking_reservations.create!(date: day, customer: customer)

        delete portal_coworking_reservation_path(res)

        expect(CoworkingReservation.unscoped.find(res.id).deleted_at).to be_present
        expect(pack.reload.days_remaining).to eq(1)

        # Re-réservation immédiate possible sur le crédit libéré.
        post portal_coworking_reservations_path, params: { date: day.iso8601 }
        expect(pack.reload.days_used).to eq(1)
      end
    end

    it "refuse l'annulation après 8h le jour même" do
      travel_to at_brussels(day, 9) do
        customer = sign_in_coworking("ana@example.com")
        pack = paid_pack(customer, days: 1)
        res = pack.coworking_reservations.create!(date: day, customer: customer)

        delete portal_coworking_reservation_path(res)
        follow_redirect!
        expect(response.body).to include("plus annulable")
        expect(res.reload.deleted_at).to be_nil
      end
    end
  end

  describe "étanchéité entre clients" do
    it "ne permet pas d'annuler la réservation d'un autre client" do
      sign_in_coworking("ana@example.com")
      other = Customer.create!(first_name: "Bruno", email: "bruno@example.com")
      opack = paid_pack(other, days: 1)
      res = opack.coworking_reservations.create!(date: day, customer: other)

      expect {
        delete portal_coworking_reservation_path(res)
      }.to raise_error(ActiveRecord::RecordNotFound)

      expect(res.reload.deleted_at).to be_nil
    end
  end
end
