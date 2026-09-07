require "rails_helper"

# Issue #215 — inversion de l'ordre du funnel B2C. L'acompte n'est plus demandé
# à la soumission mais ICI, après qu'un humain du Pôle Accueil a regardé la
# demande. Ces exemples verrouillent ce que le service pose (Payment + statut),
# ce qu'il refuse, et le fait qu'un rejeu ne double jamais l'acompte.
RSpec.describe Stays::PreConfirmer do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }

  def build_stay(status: "pending", customer: nil, total_cents: 74_500)
    Stay.create!(customer: customer || self.customer, source: "reservation", status: status,
                 arrival_date: Date.today + 30, departure_date: Date.today + 32,
                 total_amount_cents: total_cents)
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  before { deliveries.clear }

  describe "cas nominal" do
    it "crée un Payment pending/card du montant validé et passe le séjour en pre_confirmed" do
      stay = build_stay

      service = described_class.new(stay: stay, amount_cents: 37_250)
      expect(service.run).to be(true)

      payment = service.payment
      expect(payment).to be_persisted
      expect(payment.status).to eq("pending")
      expect(payment.payment_method).to eq("card")
      expect(payment.amount_cents).to eq(37_250)
      expect(payment.stay).to eq(stay)
      expect(stay.reload.status).to eq("pre_confirmed")
    end

    it "rattache le Payment au Booking d'hébergement quand il y en a un" do
      stay = build_stay
      booking = Booking.create!(firstname: "Léa", from_date: stay.arrival_date,
                                to_date: stay.departure_date, adults: 2, status: "pending")
      stay.stay_items.create!(bookable: booking)

      service = described_class.new(stay: stay.reload, amount_cents: 37_250)
      expect(service.run).to be(true)

      expect(service.payment.booking).to eq(booking)
    end

    # Camping / espaces seuls : aucun Booking d'hébergement, et c'est légitime.
    it "n'exige aucun Booking (séjour sans hébergement classique)" do
      stay = build_stay

      service = described_class.new(stay: stay, amount_cents: 10_000)
      expect(service.run).to be(true)
      expect(service.payment.booking).to be_nil
    end

    it "envoie l'email de pré-confirmation au client, avec son lien de paiement" do
      stay = build_stay

      described_class.new(stay: stay, amount_cents: 37_250).run

      expect(deliveries.size).to eq(1)
      expect(deliveries.last.to).to eq(["guest@example.com"])
      expect(deliveries.last.subject).to match(/pré-confirmée/i)
    end
  end

  describe "montant refusé (rien créé, rien envoyé)" do
    [0, -1, -37_250].each do |amount|
      it "refuse un montant non strictement positif (#{amount})" do
        stay = build_stay

        service = described_class.new(stay: stay, amount_cents: amount)
        expect(service.run).to be(false)
        expect(service.error_message).to match(/supérieur à 0/i)
        expect(Payment.count).to eq(0)
        expect(stay.reload.status).to eq("pending")
        expect(deliveries).to be_empty
      end
    end

    it "refuse un montant supérieur au total dû du séjour" do
      stay = build_stay(total_cents: 74_500)

      service = described_class.new(stay: stay, amount_cents: 74_501)
      expect(service.run).to be(false)
      expect(service.error_message).to match(/ne peut pas dépasser/i)
      expect(Payment.count).to eq(0)
      expect(stay.reload.status).to eq("pending")
      expect(deliveries).to be_empty
    end

    it "accepte un acompte ÉGAL au total dû (paiement intégral d'avance)" do
      stay = build_stay(total_cents: 74_500)

      expect(described_class.new(stay: stay, amount_cents: 74_500).run).to be(true)
    end
  end

  describe "rejeu" do
    it "refuse un second appel sur un séjour déjà pré-confirmé, sans créer de second Payment" do
      stay = build_stay
      expect(described_class.new(stay: stay, amount_cents: 37_250).run).to be(true)

      service = described_class.new(stay: stay.reload, amount_cents: 37_250)
      expect(service.run).to be(false)
      expect(service.error_message).to match(/déjà été pré-confirmé/i)
      expect(stay.reload.payments.count).to eq(1)
    end

    it "refuse un séjour déjà confirmé" do
      stay = build_stay(status: "confirmed")

      service = described_class.new(stay: stay, amount_cents: 37_250)
      expect(service.run).to be(false)
      expect(service.error_message).to match(/en attente/i)
      expect(Payment.count).to eq(0)
    end
  end

  describe "client injoignable" do
    # L'email est obligatoire à la création d'un Customer, mais l'historique
    # importé en porte sans : on reproduit cet état en contournant la validation.
    it "refuse un client sans adresse email" do
      sans_email = Customer.new(first_name: "Anonyme", customer_type: "individual")
      sans_email.save!(validate: false)
      stay = build_stay(customer: sans_email)

      service = described_class.new(stay: stay, amount_cents: 37_250)
      expect(service.run).to be(false)
      expect(service.error_message).to match(/pas d'adresse email/i)
      expect(Payment.count).to eq(0)
      expect(deliveries).to be_empty
    end

    # Fourre-tout : l'adresse est une boîte MAISON. Lui réclamer un acompte
    # écrirait aux 4 Sources à propos du séjour de quelqu'un d'autre.
    it "refuse un client fourre-tout" do
      catch_all = Customer.create!(email: Customer::CATCH_ALL_EMAILS.first,
                                   customer_type: "individual")
      stay = build_stay(customer: catch_all)

      service = described_class.new(stay: stay, amount_cents: 37_250)
      expect(service.run).to be(false)
      expect(service.error_message).to match(/fourre-tout/i)
      expect(Payment.count).to eq(0)
      expect(deliveries).to be_empty
    end
  end

  describe ".suggested_amount_cents" do
    it "propose le taux d'acompte du barème sur la part hors activités, arrondie à l'euro" do
      stay = build_stay(total_cents: 74_500)

      # 50 % de 745 € = 372,50 € → arrondi à l'euro supérieur = 373 €.
      expect(described_class.suggested_amount_cents(stay)).to eq(37_300)
    end

    it "renvoie 0 quand il n'y a rien à facturer" do
      stay = build_stay(total_cents: 0)

      expect(described_class.suggested_amount_cents(stay)).to eq(0)
    end
  end

  # L'email part HORS transaction : un incident Postmark ne doit jamais annuler
  # une pré-confirmation déjà posée.
  describe "échec d'envoi de l'email" do
    it "conserve le Payment et le statut, et remonte l'erreur" do
      allow(ReservationMailer).to receive(:pre_confirmation).and_raise(StandardError, "Postmark indisponible")
      allow(Sentry).to receive(:capture_exception)
      stay = build_stay

      service = described_class.new(stay: stay, amount_cents: 37_250)
      expect(service.run).to be(true)

      expect(service.email_error).to be_present
      expect(stay.reload.status).to eq("pre_confirmed")
      expect(stay.payments.count).to eq(1)
    end
  end
end
