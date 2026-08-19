require "rails_helper"

# Le grand livre replié à la maille où il se lit.
#
# L'invariant : replier ne doit RIEN perdre. La somme des groupes vaut la somme
# des écritures, et chaque écriture appartient à exactement un groupe — sans
# quoi le total du compte cesserait de correspondre à ce qui est affiché.
RSpec.describe MemberAccounts::GroupedLedger do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  def ecriture(date, cents, flow: "bar", label: "Conso")
    account.account_entries.create!(entry_date: date, amount_cents: cents, flow: flow, label: label)
  end

  subject(:livre) { described_class.new(account.account_entries.recent_first) }

  it "replie les consommations d'un même canal sur un même mois" do
    ecriture(Date.new(2026, 7, 3), 400, label: "Moinette")
    ecriture(Date.new(2026, 7, 18), 600, label: "Café")
    ecriture(Date.new(2026, 7, 20), 250, label: "Chips")

    expect(livre.groupes.size).to eq(1)
    groupe = livre.groupes.sole
    expect(groupe.label).to eq("Bar")
    expect(groupe.amount_cents).to eq(1_250)
    expect(groupe.entries.size).to eq(3)
    expect(groupe).to be_replie
  end

  it "sépare les canaux et les mois" do
    ecriture(Date.new(2026, 7, 3), 400, flow: "bar")
    ecriture(Date.new(2026, 7, 4), 200, flow: "bar")
    ecriture(Date.new(2026, 7, 3), 900, flow: "grocery")
    ecriture(Date.new(2026, 7, 6), 100, flow: "grocery")
    ecriture(Date.new(2026, 8, 3), 500, flow: "bar")
    ecriture(Date.new(2026, 8, 4), 500, flow: "bar")

    expect(livre.groupes.map(&:label)).to contain_exactly("Bar", "Bar", "Épicerie")
    expect(livre.groupes.map { |g| [g.month, g.flow] }.uniq.size).to eq(3)
    expect(livre.groupes.map(&:amount_cents)).to contain_exactly(1_000, 600, 1_000)
  end

  # Une écriture seule ne gagne rien à être repliée : ce serait un clic de plus
  # pour révéler la ligne qu'on voyait déjà.
  it "montre une écriture isolée telle quelle, avec SON libellé" do
    ecriture(Date.new(2026, 7, 31), 35_000, flow: "charges", label: "Loyer")

    groupe = livre.groupes.sole
    expect(groupe).not_to be_replie
    expect(groupe.label).to eq("Loyer")
  end

  # Le point qui n'est pas symétrique : un virement fondu dans un total mensuel
  # devient précisément ce qu'on ne peut plus retrouver.
  it "ne replie jamais les règlements, même deux le même jour" do
    ecriture(Date.new(2026, 7, 31), -35_000, flow: "other", label: "Règlement — Virement")
    ecriture(Date.new(2026, 7, 31), -5_972, flow: "other", label: "Règlement — Virement")

    reglements = livre.groupes.select { |g| g.amount_cents.negative? }
    expect(reglements.size).to eq(2)
    expect(reglements).to all(satisfy { |g| !g.replie? })
  end

  it "ne mélange pas un avoir avec les consommations du même canal" do
    ecriture(Date.new(2026, 7, 3), 400, flow: "bar")
    ecriture(Date.new(2026, 7, 4), -400, flow: "bar", label: "Avoir")

    expect(livre.groupes.size).to eq(2)
    expect(livre.groupes.map(&:amount_cents)).to contain_exactly(400, -400)
  end

  it "classe du plus récent au plus ancien" do
    ecriture(Date.new(2026, 6, 3), 400)
    ecriture(Date.new(2026, 8, 3), 400)
    ecriture(Date.new(2026, 7, 3), 400)

    expect(livre.groupes.map(&:month)).to eq([Date.new(2026, 8, 1), Date.new(2026, 7, 1), Date.new(2026, 6, 1)])
  end

  it "range les écritures sans canal dans Divers, sans les perdre" do
    ecriture(Date.new(2026, 7, 3), 700, flow: nil, label: "Régularisation")
    ecriture(Date.new(2026, 7, 9), 300, flow: nil, label: "Autre")

    expect(livre.groupes.sole.label).to eq("Divers")
    expect(livre.groupes.sole.amount_cents).to eq(1_000)
  end

  # Le filet : replier ne perd rien.
  it "conserve la somme et le compte des écritures" do
    ecriture(Date.new(2026, 7, 3), 400, flow: "bar")
    ecriture(Date.new(2026, 7, 4), 900, flow: "grocery")
    ecriture(Date.new(2026, 7, 31), 35_000, flow: "charges", label: "Loyer")
    ecriture(Date.new(2026, 7, 31), -12_000, flow: "other", label: "Règlement")
    ecriture(Date.new(2026, 6, 2), 250, flow: "bar")

    expect(livre.groupes.sum(&:amount_cents)).to eq(account.account_entries.sum(:amount_cents))
    expect(livre.groupes.flat_map(&:entries).map(&:id).uniq.size).to eq(account.account_entries.count)
  end

  it "ne rend aucun groupe sur un compte vierge" do
    expect(livre.groupes).to be_empty
    expect(livre).not_to be_any
  end
end
