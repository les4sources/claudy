require "rails_helper"

RSpec.describe Households::LinkMembersToHumans do
  let(:household) { Household.create!(name: "Michael & Malau") }

  def member(name, human: nil, ended_on: nil)
    HouseholdMember.create!(household: household, name: name, kind: "adult",
                            human: human, started_on: Date.current - 365, ended_on: ended_on)
  end

  it "rattache un membre à la personne du même nom" do
    human = Human.create!(name: "Michael", email: "michael@example.com")
    cible = member("Michael")

    result = described_class.new(dry_run: false).run

    expect(cible.reload.human).to eq(human)
    expect(result.linked).to contain_exactly("Michael (Michael & Malau) → Michael")
  end

  it "ignore la casse et les espaces de bord" do
    human = Human.create!(name: "Béné", email: "bene@example.com")
    cible = member("  béné ")

    described_class.new(dry_run: false).run

    expect(cible.reload.human).to eq(human)
  end

  it "traite « Stéphanie » et « Steph » comme la même personne" do
    human = Human.create!(name: "Steph", email: "steph@example.com")
    cible = member("Stéphanie")

    described_class.new(dry_run: false).run

    expect(cible.reload.human).to eq(human)
  end

  it "n'écrit rien en dry-run, mais annonce ce qu'il ferait" do
    Human.create!(name: "Michael", email: "michael@example.com")
    cible = member("Michael")

    result = described_class.new.run

    expect(cible.reload.human_id).to be_nil
    expect(result.linked.size).to eq(1)
  end

  it "ne réécrit jamais un membre déjà rattaché" do
    porte = Human.create!(name: "Malau", email: "malau@example.com")
    autre = Human.create!(name: "Michael", email: "michael@example.com")
    cible = member("Michael", human: porte)

    result = described_class.new(dry_run: false).run

    expect(cible.reload.human).to eq(porte)
    expect(result.already_linked).to eq(1)
    expect(result.linked).to be_empty
    expect(autre.reload).to be_present
  end

  # `Human` valide l'unicité du nom, donc ce cas ne peut pas naître par l'app —
  # d'où le `save(validate: false)`. La garde existe quand même : un import ou un
  # assouplissement futur de cette règle ne doit pas faire choisir une personne
  # au hasard, puisque le rattachement décide à qui on doit de l'argent.
  it "ne touche à rien quand deux personnes portent le même nom" do
    Human.create!(name: "Michael", email: "michael1@example.com")
    Human.new(name: "Michael", email: "michael2@example.com").save(validate: false)
    cible = member("Michael")

    result = described_class.new(dry_run: false).run

    expect(cible.reload.human_id).to be_nil
    expect(result.ambiguous).to contain_exactly("Michael (Michael & Malau) → 2 personnes du même nom")
  end

  it "signale un membre sans personne connue, sans rien créer" do
    cible = member("Ysalie")

    expect { described_class.new(dry_run: false).run }.not_to change(Human, :count)
    expect(cible.reload.human_id).to be_nil
  end

  it "laisse de côté un membre qui a quitté le ménage" do
    Human.create!(name: "Colin", email: "colin@example.com")
    parti = member("Colin", ended_on: Date.current - 1)

    result = described_class.new(dry_run: false).run

    expect(parti.reload.human_id).to be_nil
    expect(result.linked).to be_empty
  end

  it "est idempotent : un second passage ne rattache plus rien" do
    Human.create!(name: "Michael", email: "michael@example.com")
    member("Michael")

    described_class.new(dry_run: false).run
    second = described_class.new(dry_run: false).run

    expect(second.linked).to be_empty
    expect(second.already_linked).to eq(1)
  end
end
