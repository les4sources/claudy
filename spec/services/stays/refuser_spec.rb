require "rails_helper"

# Le « non » du flux (décision Michael du 2026-09-08). Jusqu'ici l'équipe
# cliquait « Annuler le séjour », qui n'écrit RIEN au client : celui-ci
# attendait une pré-confirmation qui ne viendrait jamais. Ces exemples
# verrouillent ce que le refus POSE (statut, dates rendues, acompte neutralisé,
# note interne, email) et ce qu'il REFUSE de faire.
RSpec.describe Stays::Refuser do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }
  let(:admin) { User.create!(email: "malau@les4sources.be", password: "password123") }

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre H", level: 1)
    l
  end

  let(:arrivee) { Date.today + 30 }
  let(:depart)  { Date.today + 32 }
  let(:motif)   { "Le gîte est déjà réservé sur ces dates." }

  before { ActionMailer::Base.deliveries.clear }

  def demande(status: "pending", customer: nil)
    stay = Stay.create!(customer: customer || self.customer, source: "reservation",
                        status: status, arrival_date: arrivee, departure_date: depart,
                        total_amount_cents: 74_500)
    booking = Booking.create!(firstname: "Léa", from_date: arrivee, to_date: depart,
                              adults: 2, status: status, lodging: hulotte)
    hulotte.rooms.each do |room|
      (arrivee...depart).each { |d| Reservation.create!(booking: booking, room: room, date: d) }
    end
    stay.stay_items.create!(bookable: booking)
    stay.reload
  end

  describe "cas nominal" do
    it "annule le séjour, propage aux réservables et rend les dates" do
      stay = demande(status: "pre_confirmed")
      # Le pré-confirmé tient bien ses dates avant le refus.
      stay.bookables.each { |b| b.update!(status: "pre_confirmed") }
      expect(hulotte.reload.available_between?(arrivee, depart)).to be(false)

      service = described_class.new(stay: stay, reason: motif, by: admin)
      expect(service.run).to be(true)

      expect(stay.reload.status).to eq("canceled")
      expect(stay.bookables.map(&:status).uniq).to eq(["canceled"])
      expect(hulotte.reload.available_between?(arrivee, depart)).to be(true)
    end

    it "refuse aussi une demande simplement EN ATTENTE" do
      stay = demande(status: "pending")

      expect(described_class.new(stay: stay, reason: motif, by: admin).run).to be(true)
      expect(stay.reload.status).to eq("canceled")
    end

    it "envoie l'email de refus au client, avec le motif" do
      stay = demande

      service = described_class.new(stay: stay, reason: motif, by: admin)
      expect(service.run).to be(true)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["guest@example.com"])
      expect(mail.subject).to match(/n'a pas pu être retenue/i)
      expect(mail.text_part.body.decoded).to include(motif)
      expect(service.email_recipient).to eq("guest@example.com")
      expect(service.email_error).to be_nil
    end

    it "annule les activités encore actives (via QuickStatusUpdater)" do
      stay = demande
      experience = Experience.create!(name: "Balade avec les ânes", price_cents: 1_500)
      availability = ExperienceAvailability.create!(experience: experience,
                                                    available_on: arrivee + 1, starts_at: "14:00")
      booking = ExperienceBooking.create!(stay: stay, experience_availability: availability,
                                          participants: 2, status: "pending")

      described_class.new(stay: stay, reason: motif, by: admin).run

      expect(booking.reload.status).to eq("cancelled")
    end
  end

  describe "neutralisation des paiements en attente" do
    it "soft-delete l'acompte pending et le rend introuvable par son lien public" do
      stay = demande(status: "pre_confirmed")
      acompte = Payment.create!(stay: stay, amount_cents: 37_250,
                                status: "pending", payment_method: "card")

      expect(described_class.new(stay: stay, reason: motif, by: admin).run).to be(true)

      expect(Payment.find_by(id: acompte.id)).to be_nil
      expect { Payment.find(acompte.id) }.to raise_error(ActiveRecord::RecordNotFound)
      # La trace reste : le soft-delete n'efface pas la ligne.
      expect(Payment.unscoped.find(acompte.id).deleted_at).to be_present
    end

    # De l'argent réellement encaissé se rembourse, il ne s'efface pas — même
    # règle que `Stays::DestroyService`, qui préserve les paiements.
    it "ne touche JAMAIS un paiement déjà encaissé" do
      stay = demande(status: "pre_confirmed")
      paye = Payment.create!(stay: stay, amount_cents: 20_000,
                             status: "paid", payment_method: "transfer")

      described_class.new(stay: stay, reason: motif, by: admin).run

      expect(paye.reload.deleted_at).to be_nil
      expect(stay.reload.payments.paid.count).to eq(1)
    end
  end

  describe "note interne" do
    it "ajoute une ligne horodatée avec l'auteur et le motif" do
      admin.update!(human: Human.create!(name: "Malau Dupont"))
      stay = demande

      described_class.new(stay: stay, reason: motif, by: admin).run

      notes = stay.reload.notes.to_s
      expect(notes).to include("⛔ Demande refusée le")
      expect(notes).to include("par Malau")
      expect(notes).to include("motif : #{motif}")
    end

    it "conserve la note existante et ajoute la sienne en dessous" do
      stay = demande
      stay.update!(notes: "⚠️ Demande multi-chiens (2)")

      described_class.new(stay: stay, reason: motif, by: admin).run

      notes = stay.reload.notes.to_s
      expect(notes).to start_with("⚠️ Demande multi-chiens (2)")
      expect(notes).to include("⛔ Demande refusée le")
    end

    it "retombe sur l'email quand l'admin n'a pas de Human rattaché" do
      stay = demande

      described_class.new(stay: stay, reason: motif, by: admin).run

      expect(stay.reload.notes.to_s).to include("par malau@les4sources.be")
    end
  end

  describe "refus du refus" do
    it "exige un motif" do
      stay = demande

      service = described_class.new(stay: stay, reason: "   ", by: admin)

      expect(service.run).to be(false)
      expect(service.error_message).to match(/motif/i)
      expect(stay.reload.status).to eq("pending")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "refuse un séjour déjà CONFIRMÉ — celui-là s'annule, il ne se refuse pas" do
      stay = demande(status: "confirmed")

      service = described_class.new(stay: stay, reason: motif, by: admin)

      expect(service.run).to be(false)
      expect(service.error_message).to match(/en attente ou pré-confirmée/i)
      expect(stay.reload.status).to eq("confirmed")
    end

    it "refuse un séjour déjà annulé" do
      stay = demande(status: "canceled")

      expect(described_class.new(stay: stay, reason: motif, by: admin).run).to be(false)
    end

    it "refuse un séjour supprimé" do
      stay = demande
      stay.update_column(:deleted_at, Time.current)

      service = described_class.new(stay: stay, reason: motif, by: admin)

      expect(service.run).to be(false)
      expect(service.error_message).to match(/supprimé/i)
    end
  end

  describe "garde-fous d'envoi (miroir de PreConfirmer)" do
    it "refuse tout de même, sans email, pour un client FOURRE-TOUT" do
      fourre_tout = Customer.create!(email: Customer::CATCH_ALL_EMAILS.first, first_name: "Boîte")
      stay = demande(customer: fourre_tout)

      service = described_class.new(stay: stay, reason: motif, by: admin)

      expect(service.run).to be(true)
      expect(stay.reload.status).to eq("canceled")
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(service.email_recipient).to be_nil
    end

    it "refuse tout de même, sans email, pour un client SANS adresse" do
      sans_email = Customer.create!(email: nil, first_name: "Jean", last_name: "Sanmail")
      stay = demande(customer: sans_email)

      service = described_class.new(stay: stay, reason: motif, by: admin)

      expect(service.run).to be(true)
      expect(stay.reload.status).to eq("canceled")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    # L'envoi est HORS transaction : un incident Postmark ne doit pas annuler un
    # refus déjà décidé.
    it "garde le refus quand l'envoi échoue, et le remonte via email_error" do
      stay = demande
      allow(ReservationMailer).to receive(:request_refused).and_raise(StandardError.new("Postmark indisponible"))
      allow(Sentry).to receive(:capture_exception)

      service = described_class.new(stay: stay, reason: motif, by: admin)

      expect(service.run).to be(true)
      expect(stay.reload.status).to eq("canceled")
      expect(service.email_error).to be_present
      expect(Sentry).to have_received(:capture_exception)
    end
  end
end
