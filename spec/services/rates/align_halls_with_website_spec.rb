require "rails_helper"

# Epic #234, phase 2 — le réalignement des tarifs des salles sur la page tarifs
# du site ne touche QUE les lignes restées à l'ancienne valeur de repli.
RSpec.describe Rates::AlignHallsWithWebsite do
  after { Pricing::Rates.reset! }

  def rate(key) = Rate.find_by(key: key)

  describe "les nouvelles clés de forfaits" do
    it "les crée quand la table ne les porte pas encore" do
      described_class.new(dry_run: false).run

      expect(rate("hall.petite_salle.cinq_jours").amount_cents).to eq(52_500)
      expect(rate("hall.petite_salle.deux_jours").amount_cents).to eq(27_000)
      expect(rate("hall_weekend.grande_salle.forfait_weekend").amount_cents).to eq(79_000)
      expect(rate("hall_weekend.cuisine_pro.deux_jours").amount_cents).to eq(28_500)
    end

    it "leur donne un libellé lisible dans Paramètres > Tarifs" do
      described_class.new(dry_run: false).run

      expect(rate("hall.petite_salle.cinq_jours").label).to eq("Petite Salle — 5 jours (semaine)")
    end
  end

  describe "les montants corrigés" do
    before { Rates::SeedFromCatalog.new.run }

    it "réaligne une ligne restée à l'ancienne valeur de repli" do
      rate("hall.petite_salle.journee_et_soiree").update!(amount_cents: 20_000)

      result = described_class.new(dry_run: false).run

      expect(rate("hall.petite_salle.journee_et_soiree").amount_cents).to eq(17_000)
      expect(result.realigned.join).to include("hall.petite_salle.journee_et_soiree")
    end

    it "LAISSE une ligne modifiée à la main et la signale" do
      rate("hall.petite_salle.journee_et_soiree").update!(amount_cents: 21_500)

      result = described_class.new(dry_run: false).run

      expect(rate("hall.petite_salle.journee_et_soiree").amount_cents).to eq(21_500)
      expect(result.kept.join).to include("hall.petite_salle.journee_et_soiree")
      expect(result.realigned.join).not_to include("hall.petite_salle.journee_et_soiree")
    end
  end

  it "n'écrit rien en dry-run" do
    Rate.create!(key: "hall.petite_salle.journee_et_soiree", amount_cents: 20_000,
                 label: "Petite Salle — journée + soirée (semaine)")

    result = nil
    expect { result = described_class.new.run }.not_to change(Rate, :count)

    expect(rate("hall.petite_salle.journee_et_soiree").amount_cents).to eq(20_000)
    expect(result.realigned.size).to eq(1)
    expect(result.created).not_to be_empty
  end

  it "est idempotente : un second passage ne change plus rien" do
    described_class.new(dry_run: false).run

    result = described_class.new(dry_run: false).run

    expect(result.created).to be_empty
    expect(result.realigned).to be_empty
    expect(result.kept).to be_empty
  end
end
