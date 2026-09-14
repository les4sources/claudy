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
  let(:cheveche) { Lodging.create!(name: "La Chevêche", price_night_cents: 27_500) }

  describe ".quote — structure de retour (AC-T2-12)" do
    it "retourne un breakdown ligne par ligne, un total et un acompte 50 % par défaut" do
      quote = described_class.quote(draft(lodging: grand_duc, nights: 2))

      expect(quote.breakdown).to be_an(Array)
      expect(quote.breakdown.first).to include(:label, :amount_cents)
      expect(quote.total_cents).to eq(130_000)         # 2 nuits semaine Grand-Duc (2 × 650 €)
      expect(quote.deposit_rate).to eq(0.5)
      expect(quote.deposit_cents).to eq(65_000)        # 50 % du total
    end

    it "permet de configurer le taux d'acompte (AC-T2-16)" do
      quote = described_class.quote(draft(lodging: grand_duc, nights: 2), deposit_rate: 0.3)
      expect(quote.deposit_cents).to eq(39_000)        # 30 % de 1 300 €
    end
  end

  # Depuis l'epic #260, les trois gîtes du site suivent le barème PUBLIÉ (cinq
  # briques datées) et non plus la formule « première nuit + nuits suivantes ».
  # Un draft sans dates est ancré sur un lundi : les nuits d'un séjour de N
  # nuits sont donc lundi, mardi… — le cas nominal du site.
  describe "barème du site, draft sans dates (epic #260)" do
    {
      1 => 65_000,   # nuit du lundi
      2 => 130_000,  # 2 nuits semaine
      3 => 195_000,  # 3 nuits semaine
      4 => 241_000,  # forfait 4 nuits (lundi → vendredi)
      6 => 290_000   # forfait 6 nuits (lundi → dimanche)
    }.each do |nights, expected_cents|
      it "Grand-Duc, #{nights} nuits = #{expected_cents / 100} €" do
        quote = described_class.quote(draft(lodging: grand_duc, nights: nights))
        expect(quote.total_cents).to eq(expected_cents)
      end
    end

    it "libelle les forfaits avec leur plage de dates" do
      quote = described_class.quote(draft(lodging: grand_duc, nights: 4))

      expect(quote.breakdown.first[:label]).to include("forfait du lundi au vendredi (4 nuits)")
    end

    it "nomme la nuit à l'unité par sa date" do
      quote = described_class.quote(draft(lodging: grand_duc, nights: 1))

      expect(quote.breakdown.first[:label]).to include("nuit du")
    end
  end

  describe "le forfait semaine du Grand-Duc reste retiré (décision 2026-09-08)" do
    # À 2 410 €, sept nuits coûtaient MOINS que quatre (2 550 €) — un barème qui
    # décroît quand le séjour s'allonge. Le nouveau barème ne le réintroduit pas.
    it "7 nuits coûtent plus que 4 nuits" do
      quatre = described_class.quote(draft(lodging: grand_duc, nights: 4)).total_cents
      sept   = described_class.quote(draft(lodging: grand_duc, nights: 7)).total_cents

      expect(sept).to be > quatre
    end
  end

  # ⚠️ TROU CONNU DU BARÈME PUBLIÉ, en saison basse seulement (15 nov – 14 mars) :
  # Mon → Sam (5 nuits) = forfait 4 nuits + la nuit du vendredi à l'unité, soit
  # PLUS cher que Mon → Dim (6 nuits), qui a son forfait. Le site vend les deux
  # à ces prix ; l'epic #260 ne tranche pas le cas. On le FIGE ici pour qu'il
  # soit visible plutôt que découvert par un client (cf. commentaire sur #260).
  describe "5 nuits en saison basse coûtent plus cher que 6" do
    let(:lundi_basse_saison) { Date.new(2027, 1, 4) } # un lundi, saison basse

    def dated(nights)
      described_class.quote(draft(lodging: grand_duc, nights: nights,
                                  arrival_date: lundi_basse_saison,
                                  departure_date: lundi_basse_saison + nights)).total_cents
    end

    it "le constate sur le Grand-Duc" do
      expect(lundi_basse_saison.wday).to eq(1)
      expect(dated(5)).to eq(241_000 + 75_000) # 3 160 €
      expect(dated(6)).to eq(290_000)          # 2 900 €
      expect(dated(5)).to be > dated(6)
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
    it "forfait/nuit (hébergement) — Hulotte 1 nuit semaine = 400 € (barème du site, epic #260)" do
      quote = described_class.quote(draft(lodging: hulotte, nights: 1))
      expect(quote.total_cents).to eq(40_000)
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

    describe "remise DUO Grande + Petite salle (décision Michael 2026-07-20)" do
      it "duo journée SEMAINE — 1 ligne « Les 2 salles (duo) » = 390 € (au lieu de 430 €)" do
        quote = described_class.quote(draft(halls: [
          { kind: "grande_salle", date: "2026-09-01", period: "journee" },
          { kind: "petite_salle", date: "2026-09-01", period: "journee" }
        ]))
        expect(quote.total_cents).to eq(39_000)
        expect(quote.breakdown.size).to eq(1)
        expect(quote.breakdown.first[:label]).to include("Les 2 salles (duo)")
        expect(quote.spaces_cents).to eq(39_000)
      end

      it "duo soirée SEMAINE = 250 €" do
        quote = described_class.quote(draft(halls: [
          { kind: "grande_salle", date: "2026-09-01", period: "soiree" },
          { kind: "petite_salle", date: "2026-09-01", period: "soiree" }
        ]))
        expect(quote.total_cents).to eq(25_000)
        expect(quote.breakdown.size).to eq(1)
      end

      # Epic #234 phase 2 : le forfait soir des deux salles vaut 90 € sur le
      # site (et non 150 €), donc 390 + 90 = 480 €.
      it "duo journée + soirée SEMAINE = 480 € (jour duo + forfait soir 90 €)" do
        quote = described_class.quote(draft(halls: [
          { kind: "grande_salle", date: "2026-09-01", period: "journee_et_soiree" },
          { kind: "petite_salle", date: "2026-09-01", period: "journee_et_soiree" }
        ]))
        expect(quote.total_cents).to eq(48_000)
        expect(quote.breakdown.size).to eq(1)
      end

      # Epic #234 phase 2 : la grille week-end est celle du site — journée +
      # forfait soir 115 € = 610 €. La journée du VENDREDI, elle, reste en
      # semaine (décision 4) ; cf. spec/services/pricing_model_halls_spec.rb.
      it "duo WEEK-END (grille un samedi) — journée = 495 €, soirée = 335 €, jour+soirée = 610 €" do
        {
          "journee" => 49_500, "soiree" => 33_500, "journee_et_soiree" => 61_000
        }.each do |period, expected|
          quote = described_class.quote(draft(
            arrival_date: Date.parse("2026-09-05"),      # samedi (week-end)
            departure_date: Date.parse("2026-09-05"),
            space_slots: { "grande_salle" => [period], "petite_salle" => [period] }
          ))
          expect(quote.total_cents).to eq(expected), "période #{period}"
          expect(quote.breakdown.size).to eq(1)
          expect(quote.breakdown.first[:label]).to include("Les 2 salles (duo)")
        end
      end

      it "PAS de duo si périodes différentes le même jour — somme normale, 2 lignes" do
        quote = described_class.quote(draft(halls: [
          { kind: "grande_salle", date: "2026-09-01", period: "journee" }, # 290 €
          { kind: "petite_salle", date: "2026-09-01", period: "soiree" }   #  90 €
        ]))
        expect(quote.total_cents).to eq(38_000)
        expect(quote.breakdown.size).to eq(2)
        expect(quote.breakdown.map { |l| l[:label] }.join).not_to include("duo")
      end

      it "PAS de duo si dates différentes — somme normale (grande le 1er, petite le 2)" do
        quote = described_class.quote(draft(halls: [
          { kind: "grande_salle", date: "2026-09-01", period: "journee" }, # 290 €
          { kind: "petite_salle", date: "2026-09-02", period: "journee" }  # 140 €
        ]))
        expect(quote.total_cents).to eq(43_000)
        expect(quote.breakdown.size).to eq(2)
      end

      it "invariant #79 sur un séjour composite avec duo : bundle + spaces == total hors activités" do
        quote = described_class.quote(draft(
          lodging: hulotte, nights: 1,                       # 485 €
          halls: [
            { kind: "grande_salle", date: "2026-09-01", period: "journee" },
            { kind: "petite_salle", date: "2026-09-01", period: "journee" }, # duo 390 €
            { kind: "cuisine_pro",  date: "2026-09-01", period: "journee" }  # 110 €
          ]
        ))
        expect(quote.spaces_cents).to eq(50_000)             # duo 390 + cuisine 110
        expect(quote.lodging_bundle_cents).to eq(40_000)     # Hulotte, 1 nuit semaine
        expect(quote.lodging_bundle_cents + quote.spaces_cents)
          .to eq(quote.total_excluding_experiences_cents)
        expect(quote.total_cents).to eq(90_000)
      end
    end

    it "€/pers (repas végé midi) — 10 pers × 15 € = 150 €" do
      quote = described_class.quote(draft(meals: [{ kind: "repas", people: 10 }]))
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
        meals: [{ kind: "repas", people: 2 }],
        dogs_count: 1
      ))
      # 400 € + (2×1×7,50) 15 € + (2×15) 30 € + 50 € = 495 €
      expect(quote.total_cents).to eq(49_500)
      expect(quote.breakdown.size).to eq(4)
    end
  end
end
