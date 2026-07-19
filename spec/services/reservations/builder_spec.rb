require "rails_helper"

RSpec.describe Reservations::Builder do
  # Hébergement réservable avec une chambre, pour que available_between? réponde
  # vrai sur la fenêtre choisie.
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    room = Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << room
    lodging
  end

  let(:arrival) { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601,
      departure_date: departure.iso8601,
      dogs_count: 0,
      first_name: "Camille",
      last_name: "Martin",
      email: "Camille@Example.com",
      phone: "+32470112233"
    }.merge(overrides))
  end

  # ------------------------------------------------------------------------
  # Epic #26, Phase 2 — Stay-first : le Booking redevient une simple OCCUPATION
  # d'hébergement. Un séjour sans hébergement ne crée plus de « Booking fantôme »,
  # et le paiement est rattaché au Stay dans tous les cas.
  # ------------------------------------------------------------------------
  describe "#run — Stay-first (epic #26)" do
    context "séjour AVEC hébergement" do
      it "crée un Booking d'occupation (le calendrier reste bloqué) et rattache le paiement au Stay" do
        builder = described_class.new(draft: draft)
        expect(builder.run).to be(true)

        expect(builder.booking).to be_persisted
        expect(builder.booking.lodging_id).to eq(hulotte.id)
        expect(builder.stay.stay_items.map(&:bookable)).to include(builder.booking)
        expect(builder.payment.stay).to eq(builder.stay)
      end
    end

    context "séjour SANS hébergement (camping seul)" do
      let(:camping_draft) do
        draft(lodging_id: nil, per_night_resources: { "tente" => ["2", "2"] })
      end

      it "ne crée AUCUN Booking d'hébergement (le camping est persisté à part)" do
        builder = described_class.new(draft: camping_draft)
        expect(builder.run).to be(true)

        # Aucun Booking d'hébergement (le « Booking fantôme » ne réapparaît pas)…
        expect(builder.booking).to be_nil
        expect(builder.stay.stay_items.where(bookable_type: "Booking")).to be_empty
        # …mais le camping public est désormais persisté sur son propre modèle (issue #79).
        expect(builder.stay.stay_items.where(bookable_type: "CampingBooking").count).to eq(1)
      end

      it "rattache quand même le paiement au Stay" do
        builder = described_class.new(draft: camping_draft)
        builder.run

        expect(builder.payment).to be_persisted
        expect(builder.payment.booking).to be_nil
        expect(builder.payment.stay).to eq(builder.stay)
        expect(builder.stay.payments).to include(builder.payment)
      end
    end

    context "séjour vide (ni hébergement ni emplacement)" do
      it "est refusé" do
        builder = described_class.new(draft: draft(lodging_id: nil))

        expect(builder.run).to be(false)
        # Issue #80 : message élargi (hébergement / espace / activité / repas).
        expect(builder.error_message).to match(/hébergement, un espace, une activité ou un repas/i)
      end
    end
  end

  describe "#run (succès)" do
    it "crée un Stay pending source=reservation (PAS d'auto-confirm — Q5/AC-T2-19)" do
      builder = described_class.new(draft: draft)
      expect(builder.run).to be(true)

      stay = builder.stay
      expect(stay.status).to eq("pending")
      expect(stay.source).to eq("reservation")
      expect(stay.source).not_to eq(stay.legacy_origin) # distinct (AC-T2-22b)
    end

    it "upsert le Customer par email lowercase (AC-T2-18)" do
      described_class.new(draft: draft).run
      described_class.new(draft: draft(first_name: "Cam")).run

      customers = Customer.where(email: "camille@example.com")
      expect(customers.count).to eq(1)
      expect(customers.first.stays.count).to eq(2)
    end

    it "crée un Booking item + un Payment pending = acompte 50 % (réutilise l'infra Stripe)" do
      builder = described_class.new(draft: draft)
      builder.run

      expect(builder.booking).to be_persisted
      expect(builder.stay.stay_items.map(&:bookable)).to include(builder.booking)
      expect(builder.payment.status).to eq("pending")
      # Hulotte 2 nuits = 485 + 260 = 745 € ; acompte 50 % = 372,50 €.
      expect(builder.payment.amount_cents).to eq(37_250)
      # issue #26 : le Payment porte aussi le lien direct vers le Stay.
      expect(builder.payment.stay).to eq(builder.stay)
      expect(builder.stay.payments).to include(builder.payment)
    end
  end

  describe "supplément chien plafonné (Q2 — AC-T2-09b / AC-T2-15)" do
    it "facture un seul chien même si plusieurs demandés et consigne pour Malau" do
      one = described_class.new(draft: draft(dogs_count: 1)).tap(&:run).stay.total_amount_cents
      many_builder = described_class.new(draft: draft(dogs_count: 3))
      many_builder.run
      many = many_builder.stay.total_amount_cents

      expect(many).to eq(one)                       # pas de 3× 50 €
      expect(many_builder.multi_dogs?).to be(true)
      expect(many_builder.stay.notes).to match(/multi.?chiens/i)
    end
  end

  describe "#run (échecs — pas d'écriture)" do
    it "refuse sans email exploitable" do
      builder = described_class.new(draft: draft(email: ""))
      expect(builder.run).to be(false)
      expect(Stay.count).to eq(0)
      expect(builder.error_message).to include("email")
    end

    it "refuse des dates indisponibles" do
      # Occupe la Hulotte sur la fenêtre.
      occ = Booking.create!(firstname: "Occ", from_date: arrival, to_date: departure, adults: 1, status: "confirmed")
      (arrival..departure).each { |d| Reservation.create!(booking: occ, room: hulotte.rooms.first, date: d) }

      builder = described_class.new(draft: draft)
      expect(builder.run).to be(false)
      expect(builder.error_message).to include("disponibles")
      expect(Stay.count).to eq(0)
    end
  end

  # ------------------------------------------------------------------------
  # Epic #55, Phase 1 — Fondations composite : les activités n'entrent NI dans
  # le total persisté du Stay NI dans l'acompte tant qu'aucun ExperienceBooking
  # n'est créé (fix « montant fantôme »). Le devis funnel garde le total complet.
  # ------------------------------------------------------------------------
  describe "activités exclues du total persisté et de l'acompte (epic #55, Phase 1)" do
    let!(:experience) { Experience.create!(name: "Atelier vannerie", fixed_price_cents: 5_000, price_cents: 1_500) }

    def draft_with_activity
      draft(experiences: [{ id: experience.id, participants: 2 }])
    end

    it "ne persiste aucun ExperienceBooking et exclut les activités du total + acompte" do
      builder = described_class.new(draft: draft_with_activity)
      expect(builder.run).to be(true)

      # Phase 1 : le Builder ne crée pas encore les ExperienceBooking.
      expect(builder.stay.experience_bookings).to be_empty
      # Hulotte 2 nuits = 485 + 260 = 745 € ; les activités (8 000 c) n'y entrent pas.
      expect(builder.stay.total_amount_cents).to eq(74_500)
      # Acompte 50 % HORS activités = 372,50 €.
      expect(builder.payment.amount_cents).to eq(37_250)
    end

    it "expose néanmoins le total complet (activités comprises) via le devis funnel" do
      builder = described_class.new(draft: draft_with_activity)
      # 745 € hébergement + (5 000 + 1 500×2) = 8 000 c d'activité = 82 500 c affichés.
      expect(builder.quote.total_cents).to eq(82_500)
      expect(builder.quote.total_excluding_experiences_cents).to eq(74_500)
    end
  end

  # ------------------------------------------------------------------------
  # Epic #55, Phase 4 — Sélection d'activités DANS le funnel : chaque créneau
  # choisi (experience_availability_id + participants) devient un
  # ExperienceBooking `pending` rattaché au Stay. Le montant réintègre le total
  # prévu du séjour mais JAMAIS l'acompte initial (garanti Phase 1).
  # ------------------------------------------------------------------------
  describe "activités réservées au funnel (epic #55, Phase 4)" do
    let!(:experience) { Experience.create!(name: "Balade avec les ânes", fixed_price_cents: 2_000, price_cents: 1_000, max_participants: 8) }
    let!(:slot) { ExperienceAvailability.create!(experience: experience, available_on: arrival, starts_at: "10:00", max_participants: 8) }

    def draft_with_slot(participants: 3)
      draft(experiences: [{ id: experience.id, availability_id: slot.id, participants: participants }])
    end

    it "crée un ExperienceBooking pending rattaché au Stay, avec le bon nombre de participants" do
      builder = described_class.new(draft: draft_with_slot(participants: 3))
      expect(builder.run).to be(true)

      bookings = builder.stay.experience_bookings
      expect(bookings.count).to eq(1)
      eb = bookings.first
      expect(eb).to be_pending
      expect(eb.experience_availability).to eq(slot)
      expect(eb.participants).to eq(3)
    end

    it "réintègre les activités au total prévu du Stay mais JAMAIS à l'acompte" do
      builder = described_class.new(draft: draft_with_slot(participants: 3))
      builder.run

      # Hulotte 2 nuits = 745 € ; activité = 2 000 + 1 000×3 = 5 000 c.
      expect(builder.stay.total_amount_cents).to eq(74_500 + 5_000)
      # Acompte 50 % HORS activités = 372,50 € (inchangé Phase 1).
      expect(builder.payment.amount_cents).to eq(37_250)
    end

    it "ignore une entrée sans créneau (rétrocompat de l'ancienne forme experiences)" do
      builder = described_class.new(draft: draft(experiences: [{ id: experience.id, participants: 2 }]))
      expect(builder.run).to be(true)
      expect(builder.stay.experience_bookings).to be_empty
    end
  end

  # ------------------------------------------------------------------------
  # Epic #81, Phase 3 — Prix libre / override + attribution (source/platform),
  # RÉSERVÉS au canal admin. Le funnel public les ignore, même sur param forgé.
  # ------------------------------------------------------------------------
  describe "prix imposé & attribution admin (epic #81, Phase 3)" do
    it "impose le total du séjour quand un override admin est fourni" do
      builder = described_class.new(draft: draft, admin: true, price_override_cents: 99_900)
      expect(builder.run).to be(true)

      expect(builder.stay.price_override_cents).to eq(99_900)
      expect(builder.stay.total_amount_cents).to eq(99_900) # pas 74 500 (devis B2C)
    end

    it "applique le devis B2C quand aucun override n'est fourni (admin)" do
      builder = described_class.new(draft: draft, admin: true)
      expect(builder.run).to be(true)

      expect(builder.stay.price_override_cents).to be_nil
      expect(builder.stay.total_amount_cents).to eq(74_500)
    end

    it "IGNORE un override forgé côté public (admin: false)" do
      builder = described_class.new(draft: draft, price_override_cents: 1)
      expect(builder.run).to be(true)

      expect(builder.stay.price_override_cents).to be_nil     # jamais persisté hors admin
      expect(builder.stay.total_amount_cents).to eq(74_500)   # devis appliqué, override ignoré
    end

    it "propage la plateforme OTA au Booking d'occupation (admin)" do
      builder = described_class.new(draft: draft, admin: true, platform: "airbnb")
      expect(builder.run).to be(true)
      expect(builder.booking.platform).to eq("airbnb")
    end

    it "garde platform=web côté public même sur param de plateforme forgé" do
      builder = described_class.new(draft: draft, platform: "airbnb")
      expect(builder.run).to be(true)
      expect(builder.booking.platform).to eq("web")
    end

    it "propage la source d'attribution du Stay (admin)" do
      builder = described_class.new(draft: draft, admin: true, source: "ota")
      expect(builder.run).to be(true)
      expect(builder.stay.source).to eq("ota")
    end
  end
end
