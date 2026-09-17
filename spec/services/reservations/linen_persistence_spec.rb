require "rails_helper"

# Epic #260, phase 2, décision Michael 6 — les draps sont une option du séjour,
# facturée par LIT (10 € le lit simple, 20 € le lit double) et JAMAIS par nuit.
# Ils n'existaient nulle part avant : ni au devis, ni au séjour, ni sur la page
# client. Ils sont désormais devisés, persistés (`LinenOrder`) et re-lus à
# l'édition, sans jamais double-compter — même invariant que les hamacs.
RSpec.describe "Draps du séjour (epic #260, phase 2)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  # Lundi → vendredi : que des nuits de semaine, donc jamais le refus de la nuit
  # de week-end isolée (phase 1). Ancré sur un lundi pour que le spec ne dépende
  # pas du jour où il tourne.
  let(:arrival)   { (Date.today + 30).next_occurring(:monday) }
  let(:departure) { arrival + 4 }

  def draft(**overrides)
    Reservations::Draft.new({
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    }.merge(overrides))
  end

  describe "devis" do
    it "facture 2 lits simples + 1 lit double à 40 €, quelle que soit la durée" do
      quote = draft(linen_single: 2, linen_double: 1).quote

      expect(quote.linen_cents).to eq(4_000)
      expect(quote.lines.select { |l| l.category == :linen }.map(&:label))
        .to contain_exactly("Draps pour lit simple × 2", "Draps pour lit double × 1")
    end

    it "ne dépend pas du nombre de nuits — le tarif est par lit" do
      short = Reservations::Draft.new(arrival_date: arrival.iso8601,
                                      departure_date: (arrival + 1).iso8601,
                                      linen_single: 3).quote
      long  = draft(linen_single: 3).quote

      expect(short.linen_cents).to eq(3_000)
      expect(long.linen_cents).to eq(3_000)
    end

    it "ne produit aucune ligne sans draps demandés" do
      expect(draft.quote.linen_cents).to eq(0)
      expect(draft(linen_single: 0, linen_double: 0).quote.lines.map(&:category)).not_to include(:linen)
    end

    it "suit le tarif de Paramètres > Tarifs quand il est édité" do
      Rate.create!(key: "linen.single_bed", amount_cents: 1_200, label: "Draps lit simple")
      Pricing::Rates.reset!

      expect(draft(linen_single: 2).quote.linen_cents).to eq(2_400)
    ensure
      Pricing::Rates.reset!
    end
  end

  describe "persistance (Reservations::Builder)" do
    it "crée une LinenOrder par type de lit, au montant du devis" do
      builder = Reservations::Builder.new(draft: draft(lodging_id: hulotte.id, linen_single: 2, linen_double: 1))
      expect(builder.run).to be(true)

      orders = builder.stay.linen_orders.ordered
      expect(orders.map(&:kind)).to eq(%w[single_bed double_bed])
      expect(orders.map(&:quantity)).to eq([2, 1])
      expect(orders.sum(&:price_cents)).to eq(builder.quote.linen_cents)
      expect(orders.first.price_cents).to eq(2_000)
      expect(orders.last.price_cents).to eq(2_000)
    end

    it "ne crée rien quand le séjour n'a pas de draps" do
      builder = Reservations::Builder.new(draft: draft(lodging_id: hulotte.id))
      expect(builder.run).to be(true)

      expect(builder.stay.linen_orders).to be_empty
    end

    it "laisse le total du séjour ET l'acompte strictement égaux au devis" do
      full  = draft(lodging_id: hulotte.id, linen_single: 2, linen_double: 1)
      quote = full.quote

      builder = Reservations::Builder.new(draft: full)
      expect(builder.run).to be(true)
      stay = builder.stay

      expect(stay.total_amount_cents).to eq(quote.total_excluding_experiences_cents)
      expect(builder.quote.deposit_cents).to eq(quote.deposit_cents)

      # Le Booking d'hébergement ne porte PAS la part draps : elle est extraite.
      booking = stay.stay_items.where(bookable_type: "Booking").first.bookable
      expect(booking.price_cents).to eq(quote.lodging_only_cents)

      # Ventilation exhaustive : bookables + draps redonnent exactement le total.
      ventilated = stay.bookables.sum { |b| b.try(:price_cents).to_i } +
                   stay.linen_orders.sum(&:price_cents)
      expect(ventilated).to eq(stay.total_amount_cents)
    end

    it "fait entrer les draps dans l'acompte suggéré à la pré-confirmation" do
      with_linen = Reservations::Builder.new(draft: draft(lodging_id: hulotte.id, linen_single: 2, linen_double: 1))
      expect(with_linen.run).to be(true)
      without = Reservations::Builder.new(draft: draft(lodging_id: hulotte.id))
      expect(without.run).to be(true)

      expect(Stays::PreConfirmer.suggested_amount_cents(with_linen.stay))
        .to be > Stays::PreConfirmer.suggested_amount_cents(without.stay)
    end
  end

  describe "aller-retour admin (DraftReconstructor → AdminUpdater)" do
    let(:stay) do
      builder = Reservations::Builder.new(draft: draft(lodging_id: hulotte.id, linen_single: 2, linen_double: 1))
      builder.run
      builder.stay
    end

    it "relit les compteurs de draps depuis le séjour" do
      reconstructed = Stays::DraftReconstructor.call(stay)

      expect(reconstructed.linen_single).to eq(2)
      expect(reconstructed.linen_double).to eq(1)
      expect(reconstructed.quote.linen_cents).to eq(4_000)
    end

    it "ne change pas le total d'un séjour ré-enregistré à l'identique" do
      before_total = stay.reload.total_amount_cents
      reconstructed = Stays::DraftReconstructor.call(stay)

      updater = Stays::AdminUpdater.new(stay: stay, draft: reconstructed)
      expect(updater.run).to be(true)

      expect(stay.reload.total_amount_cents).to eq(before_total)
      expect(stay.linen_orders.sum(&:price_cents)).to eq(4_000)
      expect(stay.linen_orders.count).to eq(2)
    end

    it "retire les draps quand le formulaire les remet à zéro" do
      reconstructed = Stays::DraftReconstructor.call(stay)
      reconstructed.linen_single = 0
      reconstructed.linen_double = 0

      expect(Stays::AdminUpdater.new(stay: stay, draft: reconstructed).run).to be(true)

      expect(stay.reload.linen_orders).to be_empty
      expect(stay.total_amount_cents).to eq(reconstructed.quote.total_excluding_experiences_cents)
    end
  end
end
