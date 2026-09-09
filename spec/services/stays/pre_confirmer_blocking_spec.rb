require "rails_helper"

# Décision Michael du 2026-09-08 : la pré-confirmation BLOQUE les dates. Deux
# conséquences sur `Stays::PreConfirmer`, toutes deux verrouillées ici —
# il PROPAGE `pre_confirmed` aux réservables (sans quoi le veto, qui lit le
# statut des bookables, ne verrait jamais rien) et il REFUSE de poser un acompte
# sur des dates devenues indisponibles pendant l'attente.
RSpec.describe Stays::PreConfirmer, "veto de disponibilité" do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre H", level: 1)
    l
  end

  let(:arrivee) { Date.today + 30 }
  let(:depart)  { Date.today + 32 }

  before { ActionMailer::Base.deliveries.clear }

  # Un séjour en attente, composé d'un gîte (et de ses Reservation de chambres,
  # qui portent l'occupation) plus éventuellement d'une salle.
  def demande(status: "pending", lodging: hulotte, with_space: nil)
    stay = Stay.create!(customer: customer, source: "reservation", status: status,
                        arrival_date: arrivee, departure_date: depart,
                        total_amount_cents: 74_500)
    booking = Booking.create!(firstname: "Léa", from_date: arrivee, to_date: depart,
                              adults: 2, status: status, lodging: lodging)
    lodging.rooms.each do |room|
      (arrivee...depart).each { |d| Reservation.create!(booking: booking, room: room, date: d) }
    end
    stay.stay_items.create!(bookable: booking)

    if with_space
      sb = SpaceBooking.create!(firstname: "Léa", from_date: arrivee, to_date: arrivee, status: status)
      SpaceReservation.create!(space_booking: sb, space: with_space, date: arrivee, duration: "day")
      stay.stay_items.create!(bookable: sb)
    end

    stay.reload
  end

  describe "propagation du statut aux réservables" do
    it "passe le séjour ET tous ses bookables en pre_confirmed" do
      stay = demande

      service = described_class.new(stay: stay, amount_cents: 37_250)
      expect(service.run).to be(true)

      expect(stay.reload.status).to eq("pre_confirmed")
      expect(stay.bookables.map(&:status).uniq).to eq(["pre_confirmed"])
    end

    it "propage aussi aux espaces du séjour" do
      salle = Space.create!(name: "Grande Salle", capacity: 1)
      stay = demande(with_space: salle)

      expect(described_class.new(stay: stay, amount_cents: 10_000).run).to be(true)

      statuts = stay.reload.bookables.map(&:status).uniq
      expect(statuts).to eq(["pre_confirmed"])
    end

    # Contrat anti-spam : la propagation ne doit réveiller AUCUN mailer de
    # réservable. Le seul email légitime est celui du client, envoyé par le
    # service lui-même.
    it "n'envoie que l'email de pré-confirmation, aucun email de réservable" do
      stay = demande

      described_class.new(stay: stay, amount_cents: 37_250).run

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.subject).to match(/pré-confirmée/i)
    end

    # C'est CE verrou qui empêche le double-booking : une fois pré-confirmée, la
    # demande tient le gîte contre toute autre.
    it "rend le gîte indisponible pour les mêmes dates" do
      stay = demande
      expect(hulotte.available_between?(arrivee, depart)).to be(true)

      described_class.new(stay: stay, amount_cents: 37_250).run

      expect(hulotte.reload.available_between?(arrivee, depart)).to be(false)
    end

    # « Repasser en attente » depuis la fiche : le séjour doit RENDRE ses dates.
    it "libère les dates quand QuickStatusUpdater le repasse en attente" do
      stay = demande
      described_class.new(stay: stay, amount_cents: 37_250).run
      expect(hulotte.reload.available_between?(arrivee, depart)).to be(false)

      expect(Stays::QuickStatusUpdater.new(stay: stay.reload, status: "pending").run).to be(true)

      expect(stay.reload.bookables.map(&:status).uniq).to eq(["pending"])
      expect(hulotte.reload.available_between?(arrivee, depart)).to be(true)
    end

    # Le chemin nominal d'après : Stripe encaisse et confirme depuis
    # `pre_confirmed`. La propagation doit continuer de fonctionner.
    it "laisse QuickStatusUpdater confirmer depuis pre_confirmed" do
      stay = demande
      described_class.new(stay: stay, amount_cents: 37_250).run

      expect(Stays::QuickStatusUpdater.new(stay: stay.reload, status: "confirmed").run).to be(true)

      expect(stay.reload.status).to eq("confirmed")
      expect(stay.bookables.map(&:status).uniq).to eq(["confirmed"])
    end
  end

  describe "refus quand les dates ne sont plus libres" do
    # Le cas réel : la demande a dormi dans la file pendant qu'un autre séjour
    # était confirmé sur les mêmes nuits.
    def occupe_le_gite(status: "confirmed")
      autre = Booking.create!(firstname: "Autre", from_date: arrivee, to_date: depart,
                              adults: 2, status: status, lodging: hulotte)
      hulotte.rooms.each do |room|
        (arrivee...depart).each { |d| Reservation.create!(booking: autre, room: room, date: d) }
      end
      autre
    end

    it "refuse, nomme le gîte, et ne pose NI acompte NI statut" do
      stay = demande
      occupe_le_gite

      service = described_class.new(stay: stay, amount_cents: 37_250)
      expect(service.run).to be(false)

      expect(service.error_message).to include("ne sont plus disponibles")
      expect(service.error_message).to include("La Hulotte")
      expect(stay.reload.status).to eq("pending")
      expect(stay.payments.count).to eq(0)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "refuse aussi face à une demande concurrente seulement PRÉ-CONFIRMÉE" do
      stay = demande
      occupe_le_gite(status: "pre_confirmed")

      service = described_class.new(stay: stay, amount_cents: 37_250)

      expect(service.run).to be(false)
      expect(service.error_message).to include("La Hulotte")
    end

    it "refuse quand c'est l'ESPACE qui est pris" do
      salle = Space.create!(name: "Grande Salle", capacity: 1)
      stay = demande(with_space: salle)

      autre = SpaceBooking.create!(firstname: "Autre", from_date: arrivee, to_date: arrivee,
                                   status: "confirmed")
      SpaceReservation.create!(space_booking: autre, space: salle, date: arrivee, duration: "day")

      service = described_class.new(stay: stay, amount_cents: 10_000)

      expect(service.run).to be(false)
      expect(service.error_message).to include("Grande Salle")
    end

    # Garde-fou explicite : le séjour ne doit JAMAIS se bloquer lui-même. Ses
    # propres bookables sont encore `pending` ici, mais on vérifie que le
    # service passe même si l'un d'eux a déjà été poussé à la main en
    # `confirmed` — sinon l'action deviendrait impossible sans explication.
    it "ignore l'occupation du séjour lui-même" do
      stay = demande
      stay.bookables.each { |b| b.update!(status: "confirmed") }

      service = described_class.new(stay: stay.reload, amount_cents: 37_250)

      expect(service.run).to be(true), "refusé à tort : #{service.error_message}"
    end

    it "reste indifférent à une demande concurrente simplement EN ATTENTE" do
      stay = demande
      occupe_le_gite(status: "pending")

      expect(described_class.new(stay: stay, amount_cents: 37_250).run).to be(true)
    end
  end
end
