require "rails_helper"
require "rake"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — créer une correspondance depuis le serveur, avant que
# l'écran de la phase 2 n'existe. Idempotent : c'est ce qui permet de relancer le
# rattrapage 2026 sans se demander ce qui a déjà été fait.
RSpec.describe "stripe:seed_category_mapping" do
  include FinanceBuilders

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before { Rake::Task["stripe:seed_category_mapping"].reenable }

  let!(:revenue) { build_general_account(code: "700100", name: "Ventes épicerie", klass: 7, nature: "revenue") }
  let!(:autre) { build_general_account(code: "700200", name: "Ventes paniers", klass: 7, nature: "revenue") }
  let(:team) { Team.create!(name: "Pôle Épicerie") }

  def run_task(env)
    original_env = ENV.to_h
    original_stdout = $stdout
    $stdout = StringIO.new
    env.each { |key, value| ENV[key] = value }
    Rake::Task["stripe:seed_category_mapping"].invoke
    :ok
  rescue SystemExit
    :aborted
  ensure
    $stdout = original_stdout
    ENV.replace(original_env)
  end

  it "crée la correspondance d'une catégorie" do
    expect(run_task("ACCOUNT" => "tranche_de_vie", "CATEGORY" => "pain",
                    "GENERAL_ACCOUNT" => "700100", "TEAM_ID" => team.id.to_s)).to eq(:ok)

    mapping = StripeCategoryMapping.for("tranche_de_vie", "pain")
    expect(mapping.general_account).to eq(revenue)
    expect(mapping.team).to eq(team)
  end

  it "désigne « sans catégorie » avec CATEGORY=none" do
    run_task("ACCOUNT" => "tranche_de_vie", "CATEGORY" => "none", "GENERAL_ACCOUNT" => "700100")

    expect(StripeCategoryMapping.for("tranche_de_vie", nil)).to be_present
  end

  it "est idempotent : relancer met à jour au lieu de dupliquer" do
    run_task("ACCOUNT" => "tranche_de_vie", "CATEGORY" => "pain", "GENERAL_ACCOUNT" => "700100")
    Rake::Task["stripe:seed_category_mapping"].reenable
    run_task("ACCOUNT" => "tranche_de_vie", "CATEGORY" => "pain", "GENERAL_ACCOUNT" => "700200")

    expect(StripeCategoryMapping.for_account("tranche_de_vie").count).to eq(1)
    expect(StripeCategoryMapping.for("tranche_de_vie", "pain").general_account).to eq(autre)
  end

  it "s'arrête quand le compte général n'existe pas" do
    expect(run_task("ACCOUNT" => "tranche_de_vie", "CATEGORY" => "pain",
                    "GENERAL_ACCOUNT" => "999999")).to eq(:aborted)
    expect(StripeCategoryMapping.count).to eq(0)
  end
end
