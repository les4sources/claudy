require "rails_helper"

# Issue #124 — les tarifs viennent de la base d'abord, des constantes en repli.
RSpec.describe "Tarifs paramétrés (Pricing::Rates)" do
  # Draft composite : hébergement + camping + van + salle + repas + terrasse +
  # pizza party + chien. Il touche TOUTES les familles de tarifs paramétrées.
  def composite_draft
    lodging = Lodging.find_by(name: "La Hulotte") ||
              Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)

    Reservations::Draft.new(
      lodging_id: lodging.id,
      arrival_date: Date.new(2026, 9, 7),   # lundi → tarifs semaine
      departure_date: Date.new(2026, 9, 10),
      dogs_count: 1,
      campings: [{ kind: "tente", people: 3, nights: 2 }],
      vans: [{ nights: 2 }],
      halls: [{ kind: "grande_salle", date: "2026-09-08", period: "journee" }],
      meals: [{ kind: "buffet", people: 4 }],
      terrasses: [{ date: "2026-09-09", people: 5 }],
      pizza_parties: [{ people: 6 }]
    )
  end

  before { Pricing::Rates.reset! }

  describe "invariance après le seed" do
    it "produit exactement le même devis avant et après rates:seed_from_catalog" do
      before_quote = PricingModel.quote(composite_draft)

      Rates::SeedFromCatalog.new.run

      after_quote = PricingModel.quote(composite_draft)

      expect(after_quote.total_cents).to eq(before_quote.total_cents)
      expect(after_quote.deposit_cents).to eq(before_quote.deposit_cents)
      expect(after_quote.breakdown).to eq(before_quote.breakdown)
    end

    it "est idempotent : rejouer le seed ne crée aucun doublon" do
      Rates::SeedFromCatalog.new.run
      expect { Rates::SeedFromCatalog.new.run }.not_to change(Rate, :count)
    end

    it "matérialise toutes les familles de tarifs du catalogue" do
      Rates::SeedFromCatalog.new.run

      %w[
        lodging.la_hulotte.first_night
        lodging.le_grand_duc.package_7
        hall.grande_salle.journee
        hall_weekend.grande_salle.journee
        hall.deux_salles.journee
        camping.tente_per_person_night
        van.per_night
        terrace.per_person_day
        hamac.simple
        meal.repas_vege_midi.per_person
        meal.buffet.per_person
        coworking.pack_1
        dog.supplement
        deposit.default_rate
      ].each do |key|
        expect(Rate.find_by(key: key)).to be_present, "clé manquante : #{key}"
      end

      expect(Rate.find_by(key: "deposit.default_rate").unit).to eq("percent")
    end

    it "ne réécrit pas un montant édité par l'équipe" do
      Rates::SeedFromCatalog.new.run
      Rate.find_by(key: "van.per_night").update!(amount_cents: 2_500)

      Rates::SeedFromCatalog.new.run

      expect(Rate.find_by(key: "van.per_night").amount_cents).to eq(2_500)
    end
  end

  describe "un tarif modifié en base change le devis" do
    before { Rates::SeedFromCatalog.new.run }

    it "van : +10 €/nuit se répercute sur le total" do
      base = PricingModel.quote(composite_draft).total_cents

      Rate.find_by(key: "van.per_night").update!(amount_cents: 2_500)
      Pricing::Rates.reset!

      # 2 nuits × (25 − 15) € = +20 €
      expect(PricingModel.quote(composite_draft).total_cents).to eq(base + 2_000)
    end

    it "hébergement : la première nuit paramétrée est utilisée" do
      base = PricingModel.quote(composite_draft).total_cents

      Rate.find_by(key: "lodging.la_hulotte.first_night").update!(amount_cents: 50_000)
      Pricing::Rates.reset!

      expect(PricingModel.quote(composite_draft).total_cents).to eq(base + 1_500)
    end

    it "salle : le tarif journée paramétré est utilisé" do
      base = PricingModel.quote(composite_draft).total_cents

      Rate.find_by(key: "hall.grande_salle.journee").update!(amount_cents: 30_000)
      Pricing::Rates.reset!

      expect(PricingModel.quote(composite_draft).total_cents).to eq(base + 1_000)
    end

    it "taux d'acompte : 30 % paramétré s'applique au devis" do
      Rate.find_by(key: "deposit.default_rate").update!(amount_cents: 30)
      Pricing::Rates.reset!

      quote = PricingModel.quote(composite_draft)
      expect(quote.deposit_rate).to eq(0.3)
      expect(quote.deposit_cents)
        .to eq(((quote.total_cents - quote.experiences_cents) * 0.3).round)
    end

    it "chien / camping / repas / terrasse suivent aussi la base" do
      base = PricingModel.quote(composite_draft).total_cents

      Rate.find_by(key: "dog.supplement").update!(amount_cents: 6_000)
      Rate.find_by(key: "camping.tente_per_person_night").update!(amount_cents: 850)
      Rate.find_by(key: "meal.buffet.per_person").update!(amount_cents: 1_300)
      Rate.find_by(key: "terrace.per_person_day").update!(amount_cents: 350)
      Pricing::Rates.reset!

      delta = 1_000 +                # chien +10 €
              (100 * 3 * 2) +        # camping +1 €/pers/nuit × 3 pers × 2 nuits
              (100 * 4) +            # buffet +1 €/pers × 4
              (100 * 5)              # terrasse +1 €/pers × 5
      expect(PricingModel.quote(composite_draft).total_cents).to eq(base + delta)
    end
  end

  describe "cache par requête" do
    it "ne fait qu'un seul chargement des tarifs pour un devis composite" do
      Rates::SeedFromCatalog.new.run
      Pricing::Rates.reset!

      allow(Pricing::Rates).to receive(:load_lookup).and_call_original
      PricingModel.quote(composite_draft)

      expect(Pricing::Rates).to have_received(:load_lookup).once
    end
  end
end
