require "rails_helper"
require "rake"

# Issue #156 — les deux tâches de barèmes datés. Toutes deux idempotentes : une
# nuit d'agent, un déploiement raté ou un doigt qui glisse ne doivent jamais
# réécrire un montant édité par l'équipe.
RSpec.describe "rates rake tasks", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("rates:backfill_versions")
  end

  def run_task(name, apply: nil)
    task = Rake::Task[name]
    task.reenable
    previous_apply = ENV["APPLY"]
    ENV["APPLY"] = apply
    original = $stdout
    $stdout = StringIO.new
    task.invoke
    $stdout.string
  ensure
    $stdout = original
    ENV["APPLY"] = previous_apply
  end

  describe "rates:backfill_versions" do
    let!(:rate) { Rate.create!(key: "van.per_night", amount_cents: 1_500, label: "Van") }

    it "n'écrit rien en dry-run" do
      expect { run_task("rates:backfill_versions") }.not_to change(RateVersion, :count)
      expect(RateVersion.count).to eq(0)
    end

    it "crée une version d'origine au montant courant avec APPLY=1" do
      run_task("rates:backfill_versions", apply: "1")

      version = rate.rate_versions.sole
      expect(version.amount_cents).to eq(1_500)
      expect(version.active_from).to eq(RateVersion::ORIGIN)
      expect(version.active_until).to be_nil
    end

    it "est idempotent : un second passage ne crée aucune version" do
      run_task("rates:backfill_versions", apply: "1")

      expect { run_task("rates:backfill_versions", apply: "1") }.not_to change(RateVersion, :count)
    end

    it "ne touche pas à un tarif déjà versionné" do
      rate.rate_versions.create!(amount_cents: 1_200, active_from: Date.new(2024, 1, 1))

      run_task("rates:backfill_versions", apply: "1")

      expect(rate.rate_versions.count).to eq(1)
      expect(rate.reload.amount_cents).to eq(1_500)
    end
  end

  describe "rates:seed_sourciers" do
    it "crée les onze clés du barème sourcier" do
      run_task("rates:seed_sourciers")

      expect(Rate.find_by(key: "bar.member_markup").unit).to eq("percent")
      expect(Rate.find_by(key: "bar.member_markup").amount_cents).to eq(110)
      expect(Rate.find_by(key: "grocery.member_ratio").amount_cents).to eq(95)
      expect(Rate.find_by(key: "grocery.public_ratio").amount_cents).to eq(105)
      expect(Rate.find_by(key: "meal.batchcooking.per_person").amount_cents).to eq(500)
      expect(Rate.find_by(key: "meal.collective.per_person").amount_cents).to eq(650)
      expect(Rate.find_by(key: "meal.batchcooking.cook_volunteering").amount_cents).to eq(350)
      expect(Rate.find_by(key: "pot.monthly_per_adult").amount_cents).to eq(1_000)
      expect(Rate.find_by(key: "pot.swing_share").amount_cents).to eq(500)
      expect(Rate.find_by(key: "dome.monthly_flat").amount_cents).to eq(5_000)
      expect(Rate.find_by(key: "dome.daily").amount_cents).to eq(1_000)
      expect(Rate.find_by(key: "pet.balthazar_monthly").amount_cents).to eq(3_000)
    end

    it "range les nouvelles clés dans le groupe « Sourciers » sans déplacer les repas" do
      Rate.create!(key: "meal.buffet.per_person", amount_cents: 1_200)
      run_task("rates:seed_sourciers")

      groups = Rate.grouped.to_h
      expect(groups["Sourciers"].map(&:key))
        .to match_array(%w[bar.member_markup grocery.member_ratio grocery.public_ratio
                           pot.monthly_per_adult pot.swing_share dome.monthly_flat
                           dome.daily pet.balthazar_monthly])
      expect(groups["Repas"].map(&:key)).to include("meal.buffet.per_person",
                                                    "meal.batchcooking.per_person")
    end

    it "borne la part balançoire au 30 avril 2027, sans date codée en Ruby" do
      run_task("rates:seed_sourciers")
      Pricing::Rates.reset!

      expect(Pricing::Rates.cents("pot.swing_share", on: Date.new(2027, 4, 30))).to eq(500)
      expect(Pricing::Rates.cents("pot.swing_share", on: Date.new(2027, 5, 1))).to be_nil
    end

    it "est idempotent : deux passages ne modifient ni les montants ni les versions" do
      run_task("rates:seed_sourciers")
      Rate.find_by(key: "dome.daily").update!(amount_cents: 1_500)

      expect { run_task("rates:seed_sourciers") }.not_to change(Rate, :count)
      expect { run_task("rates:seed_sourciers") }.not_to change(RateVersion, :count)
      expect(Rate.find_by(key: "dome.daily").amount_cents).to eq(1_500)
    end
  end
end
