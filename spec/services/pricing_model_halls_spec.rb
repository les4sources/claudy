require "rails_helper"

# Epic #234, phase 2 — le barème des salles est celui de la page tarifs du site
# (https://www.les4sources.be/sejours/tarifs, relevé le 2026-09-06). Ce fichier
# fige chaque montant nommé dans les critères d'acceptation de la phase.
RSpec.describe PricingModel, "barème des salles (epic #234 phase 2)" do
  # Semaine de référence : lundi 8 juin 2026 → dimanche 14 juin 2026.
  MONDAY    = Date.parse("2026-06-08")
  TUESDAY   = Date.parse("2026-06-09")
  WEDNESDAY = Date.parse("2026-06-10")
  THURSDAY  = Date.parse("2026-06-11")
  FRIDAY    = Date.parse("2026-06-12")
  SATURDAY  = Date.parse("2026-06-13")
  SUNDAY    = Date.parse("2026-06-14")

  def draft(**attrs)
    defaults = {
      lodging: nil, nights: 0, dogs_count: 0,
      campings: [], vans: [], halls: [], meals: [], pizza_parties: []
    }
    OpenStruct.new(defaults.merge(attrs))
  end

  # Grille cochée du `from` au `to` inclus : `slots` donne, par espace, la
  # période de chaque jour (nil = case vide).
  def quote_for(from, to, slots)
    described_class.quote(draft(arrival_date: from, departure_date: to, space_slots: slots))
  end

  def spaces_cents(from, to, slots) = quote_for(from, to, slots).spaces_cents
  def labels(from, to, slots) = quote_for(from, to, slots).breakdown.map { |l| l[:label] }

  describe "grille semaine / week-end (décision 4)" do
    it "classe la JOURNÉE du lundi au vendredi en semaine — Grande Salle 290 €" do
      [MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY].each do |date|
        expect(spaces_cents(date, date, { "grande_salle" => ["journee"] }))
          .to eq(29_000), "journée du #{date}"
      end
    end

    it "classe la SOIRÉE du lundi au jeudi en semaine — Grande Salle 190 €" do
      [MONDAY, TUESDAY, WEDNESDAY, THURSDAY].each do |date|
        expect(spaces_cents(date, date, { "grande_salle" => ["soiree"] }))
          .to eq(19_000), "soirée du #{date}"
      end
    end

    it "bascule la SOIRÉE du vendredi en week-end — Grande Salle 250 €" do
      expect(spaces_cents(FRIDAY, FRIDAY, { "grande_salle" => ["soiree"] })).to eq(25_000)
    end

    it "classe samedi et dimanche en week-end, journée comme soirée" do
      [SATURDAY, SUNDAY].each do |date|
        expect(spaces_cents(date, date, { "grande_salle" => ["journee"] })).to eq(38_000)
        expect(spaces_cents(date, date, { "grande_salle" => ["soiree"] })).to eq(25_000)
      end
    end
  end

  describe "journée + soirée = journée + forfait soir du site" do
    it "Petite Salle un lundi = 170 € (140 + 30)" do
      expect(spaces_cents(MONDAY, MONDAY, { "petite_salle" => ["journee_et_soiree"] })).to eq(17_000)
    end

    it "Grande Salle un lundi = 350 € (290 + 60)" do
      expect(spaces_cents(MONDAY, MONDAY, { "grande_salle" => ["journee_et_soiree"] })).to eq(35_000)
    end

    it "Cuisine pro un lundi = 110 € — le site n'a pas de forfait soir cuisine" do
      expect(spaces_cents(MONDAY, MONDAY, { "cuisine_pro" => ["journee_et_soiree"] })).to eq(11_000)
    end

    it "Grande Salle un samedi = 455 € (380 + 75)" do
      expect(spaces_cents(SATURDAY, SATURDAY, { "grande_salle" => ["journee_et_soiree"] })).to eq(45_500)
    end
  end

  describe "forfaits multi-jours, décomposition la moins chère (décision 5)" do
    it "Petite Salle journée du lundi au vendredi = 525 € (forfait 5 jours)" do
      expect(spaces_cents(MONDAY, FRIDAY, { "petite_salle" => Array.new(5, "journee") }))
        .to eq(52_500)
    end

    it "Petite Salle journée du lundi au jeudi = 525 € — moins cher que 2 × 270 €" do
      expect(spaces_cents(MONDAY, THURSDAY, { "petite_salle" => Array.new(4, "journee") }))
        .to eq(52_500)
    end

    it "Petite Salle journée du lundi au mercredi = 410 € (2 jours + 1 jour)" do
      expect(spaces_cents(MONDAY, WEDNESDAY, { "petite_salle" => Array.new(3, "journee") }))
        .to eq(41_000)
    end

    it "Petite Salle lundi + mardi = 270 € (forfait 2 jours)" do
      expect(spaces_cents(MONDAY, TUESDAY, { "petite_salle" => Array.new(2, "journee") }))
        .to eq(27_000)
    end

    it "Petite Salle le mardi seul = 140 €" do
      expect(spaces_cents(TUESDAY, TUESDAY, { "petite_salle" => ["journee"] })).to eq(14_000)
    end

    it "Cuisine pro journée du lundi au vendredi = 320 € (forfait 5 jours)" do
      expect(spaces_cents(MONDAY, FRIDAY, { "cuisine_pro" => Array.new(5, "journee") }))
        .to eq(32_000)
    end

    it "Grande Salle ven soirée + sam journée + soirée + dim journée + soirée = 790 €" do
      slots = { "grande_salle" => ["soiree", "journee_et_soiree", "journee_et_soiree"] }
      expect(spaces_cents(FRIDAY, SUNDAY, slots)).to eq(79_000)
    end

    it "Grande Salle le samedi journée seule = 380 € — aucun forfait ne s'applique" do
      expect(spaces_cents(SATURDAY, SATURDAY, { "grande_salle" => ["journee"] })).to eq(38_000)
    end

    it "un trou dans la suite casse le forfait : lundi + mercredi = 280 €" do
      slots = { "petite_salle" => ["journee", nil, "journee"] }
      expect(spaces_cents(MONDAY, WEDNESDAY, slots)).to eq(28_000)
    end

    it "un forfait de journées porte les soirées en supplément : lun-mar journée + soirée = 330 €" do
      # forfait 2 jours 270 € + 2 × forfait soir semaine 30 €
      slots = { "petite_salle" => Array.new(2, "journee_et_soiree") }
      expect(spaces_cents(MONDAY, TUESDAY, slots)).to eq(33_000)
    end
  end

  describe "remise duo « Les deux salles » (décision 6)" do
    it "Grande + Petite journée du lundi au vendredi = 1 400 € (forfait 5 jours duo)" do
      slots = { "grande_salle" => Array.new(5, "journee"), "petite_salle" => Array.new(5, "journee") }
      expect(spaces_cents(MONDAY, FRIDAY, slots)).to eq(140_000)
    end

    it "Grande + Petite journée un seul jour = 390 €, en une ligne" do
      slots = { "grande_salle" => ["journee"], "petite_salle" => ["journee"] }
      quote = quote_for(MONDAY, MONDAY, slots)
      expect(quote.spaces_cents).to eq(39_000)
      expect(quote.breakdown.size).to eq(1)
      expect(quote.breakdown.first[:label]).to include("Les 2 salles (duo)")
    end

    it "pas de duo si les périodes diffèrent le même jour" do
      slots = { "grande_salle" => ["journee"], "petite_salle" => ["soiree"] }
      expect(spaces_cents(MONDAY, MONDAY, slots)).to eq(29_000 + 9_000)
    end

    it "ne fusionne jamais en duo si le total non fusionné est moins cher" do
      # Grande lundi→vendredi (forfait 5 jours 990) + Petite le lundi seul (140)
      # = 1 130 €, contre duo lundi (390) + Grande mardi→vendredi (990) = 1 380 €.
      slots = { "grande_salle" => Array.new(5, "journee"), "petite_salle" => ["journee"] }
      expect(spaces_cents(MONDAY, FRIDAY, slots)).to eq(113_000)
    end
  end

  describe "lisibilité du devis" do
    it "nomme le forfait et sa plage sur une seule ligne" do
      labels = labels(MONDAY, FRIDAY, { "petite_salle" => Array.new(5, "journee") })

      expect(labels.size).to eq(1)
      expect(labels.first).to eq("Petite Salle — du lundi 8 au vendredi 12 juin, forfait 5 jours")
    end

    it "annonce les soirées ajoutées par-dessus un forfait" do
      labels = labels(MONDAY, TUESDAY, { "petite_salle" => Array.new(2, "journee_et_soiree") })

      expect(labels.first).to include("forfait 2 jours + 2 soirées")
    end

    it "garde une ligne datée par jour hors forfait" do
      labels = labels(SATURDAY, SATURDAY, { "grande_salle" => ["journee"] })

      expect(labels.size).to eq(1)
      expect(labels.first).to include("Grande Salle", "juin 2026", "journée")
    end
  end

  describe "canal `halls` (séjour sans dates) — inchangé" do
    it "reste au tarif semaine à l'unité, sans forfait, même sur cinq jours" do
      halls = (MONDAY..FRIDAY).map { |d| { kind: "petite_salle", date: d.to_s, period: "journee" } }
      quote = described_class.quote(draft(halls: halls))

      expect(quote.spaces_cents).to eq(5 * 14_000)
      expect(quote.breakdown.size).to eq(5)
    end
  end
end
