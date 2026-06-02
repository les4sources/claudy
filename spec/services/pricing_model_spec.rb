require "rails_helper"

RSpec.describe PricingModel do
  # Draft minimal duck-typé (PRD §3.2 contrat de stay_draft). On n'a pas besoin
  # d'un vrai Stay AR pour tester le moteur de pricing.
  def draft(**attrs)
    defaults = {
      lodging: nil, nights: 0, dogs_count: 0,
      campings: [], vans: [], halls: [], meals: [], pizza_parties: []
    }
    OpenStruct.new(defaults.merge(attrs))
  end

  let(:grand_duc) { Lodging.create!(name: "Le Grand-Duc", price_night_cents: 75_000) }
  let(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  describe ".quote — structure de retour (AC-T2-12)" do
    it "retourne un breakdown ligne par ligne, un total et un acompte 50 % par défaut" do
      quote = described_class.quote(draft(lodging: grand_duc, nights: 2))

      expect(quote.breakdown).to be_an(Array)
      expect(quote.breakdown.first).to include(:label, :amount_cents)
      expect(quote.total_cents).to eq(135_000)         # 2 nuits Grand-Duc
      expect(quote.deposit_rate).to eq(0.5)
      expect(quote.deposit_cents).to eq(67_500)        # 50 % du total
    end

    it "permet de configurer le taux d'acompte (AC-T2-16)" do
      quote = described_class.quote(draft(lodging: grand_duc, nights: 2), deposit_rate: 0.3)
      expect(quote.deposit_cents).to eq(40_500)        # 30 % de 1 350 €
    end
  end

  describe "formule fermée dégressive (Q3 — AC-T2-14)" do
    # Grand-Duc : nuit 1 = 750 €, nuits suivantes = 600 €.
    {
      2 => 135_000,
      3 => 195_000,
      4 => 255_000,
      5 => 315_000,
      6 => 375_000
    }.each do |nights, expected_cents|
      it "calcule #{nights} nuits = #{expected_cents / 100} € par la formule" do
        quote = described_class.quote(draft(lodging: grand_duc, nights: nights))
        expect(quote.total_cents).to eq(expected_cents)
      end
    end
  end

  describe "forfait nommé qui écrase la formule (Q3 hybride — AC-T2-14b)" do
    it "Grand-Duc 7 nuits = forfait semaine 2 410 € (override, PAS la formule)" do
      quote = described_class.quote(draft(lodging: grand_duc, nights: 7))
      formula = 75_000 + 6 * 60_000 # = 4 350 € si on appliquait la formule
      expect(quote.total_cents).to eq(241_000) # forfait semaine
      expect(quote.total_cents).not_to eq(formula)
      expect(quote.breakdown.first[:label]).to include("forfait semaine")
    end

    it "4/5/6 nuits restent calculées par la formule (pas de forfait nommé)" do
      expect(described_class.quote(draft(lodging: grand_duc, nights: 4)).total_cents).to eq(255_000)
      expect(described_class.quote(draft(lodging: grand_duc, nights: 5)).total_cents).to eq(315_000)
      expect(described_class.quote(draft(lodging: grand_duc, nights: 6)).total_cents).to eq(375_000)
    end
  end

  describe "supplément chien 50 €/séjour, plafonné à un chien (Q2 — AC-T2-15)" do
    it "ajoute 50 € pour un chien" do
      sans = described_class.quote(draft(lodging: grand_duc, nights: 2)).total_cents
      avec = described_class.quote(draft(lodging: grand_duc, nights: 2, dogs_count: 1)).total_cents
      expect(avec).to eq(sans + 5_000)
    end

    it "ne facture jamais plus d'un chien en flow auto (multi-chiens hors flow)" do
      un_chien = described_class.quote(draft(lodging: grand_duc, nights: 2, dogs_count: 1)).total_cents
      deux_chiens = described_class.quote(draft(lodging: grand_duc, nights: 2, dogs_count: 2)).total_cents
      sans = described_class.quote(draft(lodging: grand_duc, nights: 2)).total_cents
      expect(deux_chiens).to eq(un_chien)            # pas de 2× 50 €
      expect(deux_chiens).to eq(sans + 5_000)        # un seul supplément
    end
  end

  describe "chaque structure de prix supportée (AC-T2-13)" do
    it "forfait/nuit (hébergement) — Hulotte 1 nuit = 485 €" do
      quote = described_class.quote(draft(lodging: hulotte, nights: 1))
      expect(quote.total_cents).to eq(48_500)
    end

    it "€/pers/nuit (camping tente) — 4 pers × 2 nuits × 7,50 € = 60 €" do
      quote = described_class.quote(draft(campings: [{ kind: "tente", people: 4, nights: 2 }]))
      expect(quote.total_cents).to eq(6_000)
    end

    it "forfait/nuit/véhicule (van) — 3 nuits × 15 € = 45 €" do
      quote = described_class.quote(draft(vans: [{ nights: 3 }]))
      expect(quote.total_cents).to eq(4_500)
    end

    it "forfait journée (grande salle) — 1 ligne = 290 €" do
      quote = described_class.quote(draft(halls: [{ kind: "grande_salle", date: "2026-09-01", period: "journee" }]))
      expect(quote.total_cents).to eq(29_000)
    end

    it "deux lignes (grande salle soirée + petite salle journée) = 190 + 140 = 330 €" do
      quote = described_class.quote(draft(halls: [
        { kind: "grande_salle", date: "2026-09-01", period: "soiree" },
        { kind: "petite_salle", date: "2026-09-02", period: "journee" }
      ]))
      expect(quote.total_cents).to eq(33_000)
    end

    it "€/pers (repas végé midi) — 10 pers × 15 € = 150 €" do
      quote = described_class.quote(draft(meals: [{ kind: "repas_vege_midi", people: 10 }]))
      expect(quote.total_cents).to eq(15_000)
    end

    it "forfait + €/pers (Pizza Party) — 40 € + 8 pers × 7 € = 96 €" do
      quote = described_class.quote(draft(pizza_parties: [{ people: 8 }]))
      expect(quote.total_cents).to eq(9_600)
    end

    it "compose plusieurs structures dans un même devis" do
      quote = described_class.quote(draft(
        lodging: hulotte, nights: 1,
        campings: [{ kind: "tente", people: 2, nights: 1 }],
        meals: [{ kind: "repas_vege_midi", people: 2 }],
        dogs_count: 1
      ))
      # 485 € + (2×1×7,50) 15 € + (2×15) 30 € + 50 € = 580 €
      expect(quote.total_cents).to eq(58_000)
      expect(quote.breakdown.size).to eq(4)
    end
  end
end
