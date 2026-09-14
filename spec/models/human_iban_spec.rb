require "rails_helper"

# Epic #241, phase 1 — l'IBAN d'un membre. Deux choses comptent : un IBAN mal
# recopié est refusé à la saisie plutôt que découvert au retour du virement, et
# il n'est pas lisible dans un dump de base.
RSpec.describe Human, "son IBAN", type: :model do
  let(:iban) { "BE68539007547034" }

  it "accepte un IBAN valide, espaces et minuscules compris" do
    human = Human.create!(name: "Sébastien IBAN", iban: "be68 5390 0754 7034")

    expect(human.reload.iban).to eq(iban)
  end

  it "refuse un IBAN dont la clé de contrôle est fausse" do
    human = Human.new(name: "Faux IBAN", iban: "BE68539007547035")

    expect(human).not_to be_valid
    expect(human.errors[:iban].join).to include("IBAN")
  end

  it "laisse l'IBAN vide — tout le monde n'avance pas de frais" do
    expect(Human.new(name: "Sans IBAN", iban: "")).to be_valid
  end

  it "chiffre l'IBAN en base : le chercher en clair ne trouve rien" do
    human = Human.create!(name: "Chiffré", iban: iban)

    stocke = Human.connection.select_value(
      Human.sanitize_sql_array(["SELECT iban FROM humans WHERE id = ?", human.id])
    )
    expect(stocke).not_to eq(iban)
    expect(stocke).not_to include("5390")
  end

  it "n'affiche que les quatre derniers caractères" do
    human = Human.create!(name: "Masqué", iban: iban)

    expect(human.iban_masked).to eq("•••• 7034")
    expect(Human.new(name: "Vide").iban_masked).to be_nil
  end
end
