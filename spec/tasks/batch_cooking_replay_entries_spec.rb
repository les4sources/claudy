require "rails_helper"
require "rake"

# Issue #307 — le rattrapage des sessions déjà encodées.
#
# La migration renomme une colonne ; elle n'écrit AUCUNE écriture. Ce qui
# corrige la comptabilité, c'est cette tâche, lancée à la main après
# déploiement. Elle doit donc être rejouable sans rien dupliquer, et survivre à
# une session dont une écriture est verrouillée par un décompte émis.
RSpec.describe "batch_cooking:replay_entries" do
  let(:cheveche) { Household.create!(name: "Chevêche", kind: "resident") }
  let!(:compte) { MemberAccount.create!(kind: "household", household: cheveche, name: "Chevêche") }

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before do
    Rake::Task["batch_cooking:replay_entries"].reenable
    %w[meal.batchcooking.per_person meal.batchcooking.cook_volunteering]
      .zip([ 500, 350 ]).each do |key, cents|
        rate = Rate.create!(key: key, amount_cents: cents)
        rate.rate_versions.create!(amount_cents: cents, active_from: RateVersion::ORIGIN)
      end
    Pricing::Rates.reset!
  end

  def run_task
    Rake::Task["batch_cooking:replay_entries"].tap(&:reenable).invoke
  end

  # Une session posée AVANT le changement : ses écritures facturent 3 portions
  # alors que la famille compte 3 personnes sur une session à 5 repas.
  def session_sous_facturee
    seance = BatchCookingSession.create!(cooked_on: Date.new(2026, 9, 12), meals_count: 1)
    seance.servings.create!(member_account: compte, people: 3)
    Finance::RecordBatchCooking.new(session: seance).run!
    seance.update!(meals_count: 5)
    seance
  end

  it "corrige une session sous-facturée" do
    session_sous_facturee
    expect(compte.account_entries.sum(:amount_cents)).to eq(1_500)

    expect { run_task }.to output(/1 session\(s\) corrigée\(s\)/).to_stdout

    expect(compte.account_entries.sum(:amount_cents)).to eq(7_500)
    expect(compte.account_entries.first.quantity).to eq(15)
  end

  it "ne crée aucun doublon au second passage" do
    session_sous_facturee
    run_task

    expect { run_task }.not_to change(AccountEntry, :count)
    expect(compte.account_entries.sum(:amount_cents)).to eq(7_500)
  end

  it "annonce une session inchangée plutôt que de la recompter" do
    seance = BatchCookingSession.create!(cooked_on: Date.new(2026, 9, 12), meals_count: 5)
    seance.servings.create!(member_account: compte, people: 3)
    Finance::RecordBatchCooking.new(session: seance).run!

    expect { run_task }.to output(/0 session\(s\) corrigée\(s\), 1 inchangée\(s\)/).to_stdout
  end

  # Le refus est LÉGITIME : un décompte émis ne se réécrit pas. La tâche le dit
  # et continue — elle ne doit surtout pas s'arrêter sur la première.
  it "rapporte une session verrouillée sans planter, et traite quand même les autres" do
    verrouillee = session_sous_facturee
    verrouillee.reload
    AccountEntry.where(kind: "batchcooking").first.update!(locked_at: Time.current)

    autre_menage = Household.create!(name: "Merle", kind: "resident")
    autre_compte = MemberAccount.create!(kind: "household", household: autre_menage, name: "Merle")
    suivante = BatchCookingSession.create!(cooked_on: Date.new(2026, 9, 20), meals_count: 1)
    suivante.servings.create!(member_account: autre_compte, people: 2)
    Finance::RecordBatchCooking.new(session: suivante).run!
    suivante.update!(meals_count: 5)

    expect { run_task }.to output(/1 session\(s\) corrigée\(s\), 0 inchangée\(s\), 1 refusée\(s\)/).to_stdout

    expect(compte.account_entries.sum(:amount_cents)).to eq(1_500)
    expect(autre_compte.account_entries.sum(:amount_cents)).to eq(5_000)
  end
end
