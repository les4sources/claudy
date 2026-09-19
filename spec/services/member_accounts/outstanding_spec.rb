require "rails_helper"

# Le lettrage de lecture qui répond à « à quoi correspond le montant impayé ? ».
#
# L'invariant qui tient tout : quoi qu'il arrive, `total - avance` doit valoir
# le solde du compte. Une décomposition qui ne se recolle pas au solde affiché
# juste au-dessus serait pire que pas de décomposition du tout.
RSpec.describe MemberAccounts::Outstanding do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  def conso(date, cents, label: "Conso bar", flow: "bar")
    account.account_entries.create!(entry_date: date, amount_cents: cents, label: label, flow: flow)
  end

  def reglement(date, cents)
    account.account_entries.create!(entry_date: date, amount_cents: -cents, label: "Règlement")
  end

  # Le filet : il tourne sur chaque scénario ci-dessous.
  def verifie_invariant
    calcul = described_class.new(account.reload)
    expect(calcul.total_cents - calcul.advance_cents).to eq(account.balance_cents)
  end

  it "ne réclame rien sur un compte vierge" do
    calcul = described_class.new(account)

    expect(calcul.postes).to be_empty
    expect(calcul).not_to be_any
    verifie_invariant
  end

  it "porte une consommation non réglée sur son mois" do
    conso(Date.new(2026, 6, 17), 10_000, label: "Batchcooking", flow: "meal")

    calcul = described_class.new(account)

    expect(calcul.total_cents).to eq(10_000)
    expect(calcul.postes.size).to eq(1)
    expect(calcul.postes.first.month).to eq(Date.new(2026, 6, 1))
    expect(calcul.postes.first.lignes.map(&:label)).to eq(["Batchcooking"])
    verifie_invariant
  end

  it "éteint les dettes les plus anciennes d'abord" do
    conso(Date.new(2026, 4, 30), 5_000)
    conso(Date.new(2026, 5, 31), 8_000)
    reglement(Date.new(2026, 6, 5), 5_000)

    calcul = described_class.new(account)

    expect(calcul.total_cents).to eq(8_000)
    expect(calcul.postes.map(&:month)).to eq([Date.new(2026, 5, 1)])
    verifie_invariant
  end

  it "entame le mois suivant quand le règlement déborde" do
    conso(Date.new(2026, 4, 30), 5_000)
    conso(Date.new(2026, 5, 31), 8_000)
    reglement(Date.new(2026, 6, 5), 9_000)

    calcul = described_class.new(account)

    expect(calcul.total_cents).to eq(4_000)
    expect(calcul.postes.sole.month).to eq(Date.new(2026, 5, 1))
    expect(calcul.postes.sole.lignes.sole.amount_cents).to eq(4_000)
    verifie_invariant
  end

  it "ne réclame rien quand tout est réglé" do
    conso(Date.new(2026, 4, 30), 5_000)
    reglement(Date.new(2026, 5, 2), 5_000)

    calcul = described_class.new(account)

    expect(calcul).not_to be_any
    expect(calcul.postes).to be_empty
    verifie_invariant
  end

  # Un ménage qui verse une provision : le crédit précède la consommation.
  it "compte une avance, et l'absorbe à la consommation suivante" do
    reglement(Date.new(2026, 3, 1), 10_000)

    calcul = described_class.new(account)
    expect(calcul.advance_cents).to eq(10_000)
    expect(calcul).not_to be_any
    verifie_invariant

    conso(Date.new(2026, 4, 15), 12_000)

    calcul = described_class.new(account.reload)
    expect(calcul.advance_cents).to eq(0)
    expect(calcul.total_cents).to eq(2_000)
    verifie_invariant
  end

  it "traite le solde d'ouverture comme une dette datée" do
    account.update!(opening_balance_cents: 24_000, opening_balance_on: Date.new(2022, 2, 1))
    conso(Date.new(2026, 6, 30), 1_000)

    calcul = described_class.new(account)

    expect(calcul.total_cents).to eq(25_000)
    expect(calcul.postes.first.month).to eq(Date.new(2022, 2, 1))
    expect(calcul.postes.first.lignes.sole.label).to include("ouverture")
    verifie_invariant
  end

  it "sépare les mois et garde l'ordre du plus ancien au plus récent" do
    conso(Date.new(2026, 6, 30), 1_000)
    conso(Date.new(2026, 4, 30), 2_000)
    conso(Date.new(2026, 5, 31), 3_000)

    calcul = described_class.new(account)

    expect(calcul.postes.map(&:month)).to eq([Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1)])
    expect(calcul.oldest_month).to eq(Date.new(2026, 4, 1))
    expect(calcul.postes.map(&:amount_cents)).to eq([2_000, 3_000, 1_000])
    verifie_invariant
  end

  # Le cas de Béné : des charges de plusieurs mois, un règlement partiel, et
  # une facturation ponctuelle récente. C'est ce que le callout doit savoir
  # raconter pour être utile.
  it "raconte un compte réel : trois mois de charges et un batchcooking" do
    conso(Date.new(2026, 1, 31), 17_000, label: "Charges habitants", flow: "charges")
    conso(Date.new(2026, 2, 28), 17_000, label: "Charges habitants", flow: "charges")
    conso(Date.new(2026, 3, 31), 17_000, label: "Charges habitants", flow: "charges")
    conso(Date.new(2026, 6, 27), 2_500, label: "Batchcooking", flow: "meal")
    reglement(Date.new(2026, 2, 10), 17_000)

    calcul = described_class.new(account)

    expect(calcul.total_cents).to eq(36_500)
    expect(calcul.postes.map(&:month)).to eq([Date.new(2026, 2, 1), Date.new(2026, 3, 1), Date.new(2026, 6, 1)])
    expect(calcul.postes.last.lignes.sole.flow).to eq("meal")
    verifie_invariant
  end

  # Un mois de bar, c'est trente lignes à 1,95 € : déroulées dans « À régler »,
  # elles enterrent les charges et le loyer, qui sont ce qu'on vient y chercher.
  it "replie les consommations du bar en une seule ligne par mois" do
    conso(Date.new(2026, 7, 31), 800, label: "Vin rouge bouteille")
    conso(Date.new(2026, 7, 31), 195, label: "Cambrée")
    conso(Date.new(2026, 7, 31), 281, label: "Chips ReBel")
    conso(Date.new(2026, 7, 31), 35_000, label: "Loyer", flow: "charges")

    poste = described_class.new(account).postes.sole

    expect(poste.lignes.map(&:label)).to contain_exactly("Bar", "Loyer")
    bar = poste.lignes.find { |ligne| ligne.flow == "bar" }
    expect(bar.amount_cents).to eq(1_276)
    expect(bar.detail).to eq("3 consommations")
    expect(poste.amount_cents).to eq(36_276)
    verifie_invariant
  end

  it "ne replie rien quand le mois ne porte qu'une consommation de bar" do
    conso(Date.new(2026, 7, 31), 195, label: "Cambrée")

    ligne = described_class.new(account).postes.sole.lignes.sole

    expect(ligne.label).to eq("Cambrée")
    expect(ligne.detail).to eq("Bar")
    verifie_invariant
  end

  # Le repli est un affichage, pas un lettrage : il arrive APRÈS l'imputation,
  # donc une ligne de bar à moitié éteinte compte pour ce qu'il en reste.
  it "replie les restes après imputation, pas les montants d'origine" do
    conso(Date.new(2026, 7, 31), 800, label: "Vin rouge bouteille")
    conso(Date.new(2026, 7, 31), 195, label: "Cambrée")
    conso(Date.new(2026, 7, 31), 281, label: "Chips ReBel")
    reglement(Date.new(2026, 8, 2), 900)

    poste = described_class.new(account).postes.sole

    expect(poste.lignes.sole.label).to eq("Bar")
    expect(poste.lignes.sole.amount_cents).to eq(376)
    expect(poste.lignes.sole.detail).to eq("2 consommations")
    verifie_invariant
  end
end
