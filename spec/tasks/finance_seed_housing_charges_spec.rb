require "rails_helper"
require "rake"

# Un barème ne facture rien tout seul : il dit COMBIEN, la règle dit à QUI. Le
# seed pose donc les deux — sinon on lance la rake, on ouvre l'écran, et il est
# vide (c'est arrivé en prod le 2026-08-14).
RSpec.describe "finance:seed_housing_charges" do
  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before { Rake::Task["finance:seed_housing_charges"].reenable }

  def run_task
    Rake::Task["finance:seed_housing_charges"].invoke
  end

  it "crée le barème à 65 €/personne, en vigueur au 01/02/2026" do
    expect { run_task }.to output(/65/).to_stdout

    rate = Rate.find_by(key: "charges.per_person_monthly")
    expect(rate.amount_cents).to eq(6_500)
    expect(Pricing::Rates.cents("charges.per_person_monthly", on: Date.new(2026, 2, 1))).to eq(6_500)
  end

  # Pas de version avant février 2026 : les charges d'avant étaient d'un autre
  # montant, qu'on ne connaît pas. Mieux vaut ne rien résoudre que facturer faux.
  it "ne résout rien avant le 01/02/2026" do
    run_task

    expect(Pricing::Rates.cents("charges.per_person_monthly", on: Date.new(2026, 1, 31))).to be_nil
  end

  it "crée les deux règles, visant tous les ménages habitants" do
    expect { run_task }.to change(RecurringCharge, :count).by(2)

    charges = RecurringCharge.ordered
    expect(charges.map(&:label)).to contain_exactly("Charges habitants", "Cagnotte habitants")
    expect(charges.map(&:applies_to).uniq).to eq(["resident_households"])
    expect(charges.find_by(label: "Charges habitants").basis).to eq("per_person")
    expect(charges.find_by(label: "Cagnotte habitants").split_rate_key).to eq("pot.swing_share")
  end

  it "est idempotente" do
    run_task
    Rake::Task["finance:seed_housing_charges"].reenable

    expect { run_task }.not_to change(RecurringCharge, :count)
  end

  # La règle seule ne débite personne : la génération reste une action séparée.
  it "ne crée AUCUNE écriture" do
    expect { run_task }.not_to change(AccountEntry, :count)
  end
end
