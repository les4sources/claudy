require "rails_helper"

RSpec.describe Stays::MergeOriginNotes do
  def build_booking(**attrs)
    Booking.create!({
      firstname: "Zoé",
      lastname: "Durand",
      email: "zoe@example.com",
      from_date: Date.new(2026, 8, 1),
      to_date: Date.new(2026, 8, 4),
      adults: 2,
      status: "confirmed",
      price_cents: 30_000
    }.merge(attrs))
  end

  # `notes:` reste le paramètre du helper — c'est la note INTERNE, devenue du
  # texte riche (issue #313). On la pose sous la forme qu'aurait produite la
  # migration : le HTML de `simple_format`.
  def build_stay(notes: nil, bookables: [])
    customer = Customer.create!(email: "zoe@example.com", customer_type: "individual")
    stay = Stay.create!(customer: customer,
                        internal_notes: Stays::InternalNote.to_html(notes).presence,
                        arrival_date: Date.new(2026, 8, 1), departure_date: Date.new(2026, 8, 4))
    bookables.each { |b| stay.stay_items.create!(bookable: b) }
    stay
  end

  # Le TEXTE de la note interne, seule chose que ces cas ont jamais voulu vérifier :
  # le balisage est un détail de rendu, il ne fait pas partie du contrat du service.
  def note_text(stay)
    stay.reload.internal_note_text
  end

  def note_html(stay)
    Stays::InternalNote.html_for(stay.reload)
  end

  describe "rapatriement" do
    it "recopie la note de la réservation dans un séjour qui n'en a pas" do
      stay = build_stay(bookables: [build_booking(notes: "Arrivée tardive, prévoir les clés.")])

      expect(described_class.call(stay)).to be(true)
      expect(note_text(stay)).to eq("Arrivée tardive, prévoir les clés.")
    end

    it "ajoute la note d'origine SOUS celle du séjour, sans l'écraser" do
      stay = build_stay(notes: "Vu avec Malau.", bookables: [build_booking(notes: "Sans gluten.")])

      described_class.call(stay)

      expect(note_text(stay)).to eq("Vu avec Malau.\n\nSans gluten.")
    end

    it "ne touche JAMAIS à la note portée par la réservation" do
      booking = build_booking(notes: "Sans gluten.")
      stay = build_stay(bookables: [booking])

      described_class.call(stay)

      expect(booking.reload.notes).to eq("Sans gluten.")
    end

    it "réunit les notes de plusieurs réservations d'un même séjour" do
      space = SpaceBooking.create!(firstname: "Zoé", lastname: "Durand", email: "ciep@example.com",
                                   from_date: Date.new(2026, 8, 1), to_date: Date.new(2026, 8, 4),
                                   status: "confirmed", notes: "Buffet végétarien.")
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten."), space])

      described_class.call(stay)

      expect(note_text(stay)).to eq("Sans gluten.\n\nBuffet végétarien.")
    end

    it "ne garde qu'un exemplaire d'une note saisie à l'identique sur deux réservations" do
      space = SpaceBooking.create!(firstname: "Zoé", lastname: "Durand", email: "ciep@example.com",
                                   from_date: Date.new(2026, 8, 1), to_date: Date.new(2026, 8, 4),
                                   status: "confirmed", notes: "Sans gluten.")
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten."), space])

      described_class.call(stay)

      expect(note_text(stay)).to eq("Sans gluten.")
    end

    it "assemble des BLOCS HTML, un paragraphe par note d'origine" do
      space = SpaceBooking.create!(firstname: "Zoé", lastname: "Durand", email: "ciep@example.com",
                                   from_date: Date.new(2026, 8, 1), to_date: Date.new(2026, 8, 4),
                                   status: "confirmed", notes: "Buffet végétarien.")
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten."), space])

      described_class.call(stay)

      html = note_html(stay)
      expect(html).to include("<p>Sans gluten.</p>")
      expect(html).to include("<p>Buffet végétarien.</p>")
    end
  end

  describe "idempotence" do
    it "ne recopie rien une deuxième fois" do
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten.")])
      described_class.call(stay)

      expect(described_class.call(stay)).to be(false)
      expect(note_text(stay)).to eq("Sans gluten.")
    end

    it "reconnaît une note déjà recopiée à la main, à la mise en forme près" do
      stay = build_stay(notes: "Sans   gluten.", bookables: [build_booking(notes: "sans gluten.")])

      expect(described_class.call(stay)).to be(false)
      expect(note_text(stay)).to eq("Sans   gluten.")
    end

    # La comparaison porte sur le TEXTE, jamais sur le balisage : une note saisie
    # en gras dans l'éditeur ne doit pas se faire recopier une seconde fois.
    it "reconnaît une note déjà rapatriée dont le balisage a changé depuis" do
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten.")])
      stay.update!(internal_notes: "<p><strong>Sans gluten.</strong></p>")

      expect(described_class.call(stay)).to be(false)
      expect(note_html(stay)).to include("<strong>")
    end

    it "laisse intact un séjour sans aucune note" do
      stay = build_stay(bookables: [build_booking(notes: nil)])

      expect(described_class.call(stay)).to be(false)
      expect(note_text(stay)).to eq("")
      expect(ActionText::RichText.where(record: stay, name: "internal_notes")).to be_empty
    end

    # PIÈGE DE LA BASCULE : `ActionText::RichText belongs_to :record, touch: true`.
    # Enregistrer la note touche donc le séjour par défaut — le service doit s'en
    # garder explicitement (`Stay.no_touching`), comme le faisait `update_column`.
    it "n'écrit pas dans updated_at — le rapatriement n'est pas une modification éditoriale" do
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten.")])

      expect { described_class.call(stay) }.not_to change { stay.reload.updated_at }
      expect(note_text(stay)).to eq("Sans gluten.")
    end
  end
end
