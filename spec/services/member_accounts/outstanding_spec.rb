require "rails_helper"

# Le lettrage de lecture qui répond à « à quoi correspond le montant impayé ? ».
#
# L'invariant qui tient tout : quoi qu'il arrive, `total - avance` doit valoir
# le solde du compte. Une décomposition qui ne se recolle pas au solde affiché
# juste au-dessus serait pire que pas de décomposition du tout.
#
# La règle qui donne son sens au reste : un règlement éteint le POSTE qu'il
# paie, jamais un autre.
RSpec.describe MemberAccounts::Outstanding do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  def conso(date, cents, label: "Conso bar", flow: "bar")
    account.account_entries.create!(entry_date: date, amount_cents: cents, label: label, flow: flow)
  end

  def reglement(date, cents, flow: "bar")
    account.account_entries.create!(entry_date: date, amount_cents: -cents, label: "Règlement",
                                    kind: "settlement", flow: flow)
  end

  # Le filet : il tourne sur chaque scénario ci-dessous.
  def verifie_invariant
    calcul = described_class.new(account.reload)
    expect(calcul.total_cents - calcul.advance_cents).to eq(account.balance_cents)
  end

  def poste(calcul, flow) = calcul.postes.find { |p| p.flow == flow }

  it "ne réclame rien sur un compte vierge" do
    calcul = described_class.new(account)

    expect(calcul.postes).to be_empty
    expect(calcul).not_to be_any
    verifie_invariant
  end

  it "porte une consommation non réglée sur son poste" do
    conso(Date.new(2026, 6, 17), 10_000, label: "Batchcooking", flow: "meal")

    calcul = described_class.new(account)

    expect(calcul.total_cents).to eq(10_000)
    expect(calcul.postes.sole.flow).to eq("meal")
    expect(calcul.postes.sole.label).to eq("Repas")
    expect(calcul.postes.sole.lignes.map(&:label)).to eq(["Batchcooking"])
    verifie_invariant
  end

  it "éteint les dettes les plus anciennes d'abord, à l'intérieur du poste" do
    conso(Date.new(2026, 4, 30), 5_000)
    conso(Date.new(2026, 5, 31), 8_000)
    reglement(Date.new(2026, 6, 5), 5_000)

    calcul = described_class.new(account)

    expect(calcul.total_cents).to eq(8_000)
    expect(poste(calcul, "bar").lignes.sole.entry_date).to eq(Date.new(2026, 5, 31))
    verifie_invariant
  end

  # LA règle, celle qui a motivé la réécriture : « quand on fait un paiement de
  # 345 €, c'est pour payer nos charges habitants, pas pour régler d'autres
  # dettes bar ou batchcooking » (Michael, 2026-09-20).
  it "n'éteint jamais un poste avec le règlement d'un autre" do
    conso(Date.new(2026, 6, 30), 6_173, label: "Bières de juin", flow: "bar")
    conso(Date.new(2026, 7, 31), 34_500, label: "Charges habitants", flow: "charges")
    reglement(Date.new(2026, 7, 31), 34_500, flow: "charges")

    calcul = described_class.new(account)

    expect(poste(calcul, "charges")).to be_nil
    expect(poste(calcul, "bar").amount_cents).to eq(6_173)
    expect(calcul.total_cents).to eq(6_173)
    verifie_invariant
  end

  it "laisse l'excédent en avance SUR SON POSTE, sans déborder" do
    conso(Date.new(2026, 6, 30), 6_173, label: "Bières de juin", flow: "bar")
    reglement(Date.new(2026, 7, 31), 40_000, flow: "charges")

    calcul = described_class.new(account)

    expect(calcul.avances).to eq({ "charges" => 40_000 })
    expect(poste(calcul, "bar").amount_cents).to eq(6_173)
    expect(calcul.total_cents).to eq(6_173)
    expect(calcul.advance_cents).to eq(40_000)
    verifie_invariant
  end

  it "absorbe une avance à la consommation suivante du même poste" do
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

  it "ne réclame rien quand tout est réglé" do
    conso(Date.new(2026, 4, 30), 5_000)
    reglement(Date.new(2026, 5, 2), 5_000)

    calcul = described_class.new(account)

    expect(calcul).not_to be_any
    expect(calcul.postes).to be_empty
    verifie_invariant
  end

  # Un règlement dont personne ne sait ce qu'il paie ne doit pas être rangé au
  # hasard dans un poste : il tombe dans « Divers », où il se voit.
  it "range dans « Divers » un règlement sans poste" do
    conso(Date.new(2026, 6, 30), 5_000, label: "Régularisation", flow: nil)
    reglement(Date.new(2026, 7, 31), 2_000, flow: nil)

    calcul = described_class.new(account)

    expect(poste(calcul, "other").label).to eq("Divers")
    expect(poste(calcul, "other").amount_cents).to eq(3_000)
    verifie_invariant
  end

  it "traite le solde d'ouverture comme une dette datée, rangée dans « Divers »" do
    account.update!(opening_balance_cents: 24_000, opening_balance_on: Date.new(2022, 2, 1))
    conso(Date.new(2026, 6, 30), 1_000)

    calcul = described_class.new(account)

    expect(calcul.total_cents).to eq(25_000)
    expect(poste(calcul, "other").lignes.sole.label).to include("ouverture")
    expect(calcul.oldest_month).to eq(Date.new(2022, 2, 1))
    verifie_invariant
  end

  it "range les postes dans un ordre stable, « Divers » en dernier" do
    conso(Date.new(2026, 6, 30), 1_000, label: "Divers", flow: nil)
    conso(Date.new(2026, 6, 30), 2_000, label: "Batch", flow: "meal")
    conso(Date.new(2026, 6, 30), 3_000, label: "Bière", flow: "bar")
    conso(Date.new(2026, 6, 30), 4_000, label: "Charges", flow: "charges")

    calcul = described_class.new(account)

    expect(calcul.postes.map(&:flow)).to eq(%w[bar meal charges other])
    verifie_invariant
  end

  # Le compte de Béné, celui qui a motivé tout ça : des charges payées tous les
  # mois, un bar qui traîne. Le poste Charges doit être muet.
  it "raconte un compte réel : charges à jour, bar en retard" do
    3.times do |i|
      mois = Date.new(2026, 5 + i, 1).end_of_month
      conso(mois, 42_500, label: "Charges habitants", flow: "charges")
      reglement(mois, 42_500, flow: "charges")
      conso(mois, 2_000 + i, label: "Chips ReBel", flow: "bar")
    end

    calcul = described_class.new(account)

    expect(calcul.postes.map(&:flow)).to eq(["bar"])
    expect(calcul.total_cents).to eq(6_003)
    expect(calcul.oldest_month).to eq(Date.new(2026, 5, 1))
    verifie_invariant
  end

  describe "#poste" do
    it "rend le détail d'un poste, des lignes les plus anciennes aux plus récentes" do
      conso(Date.new(2026, 7, 31), 800, label: "Vin rouge")
      conso(Date.new(2026, 6, 30), 195, label: "Cambrée")

      detail = described_class.new(account).poste("bar")

      expect(detail.lignes.map(&:label)).to eq(["Cambrée", "Vin rouge"])
      expect(detail.amount_cents).to eq(995)
      expect(detail.oldest_on).to eq(Date.new(2026, 6, 30))
    end

    it "ne rend rien pour un poste soldé ou inconnu" do
      conso(Date.new(2026, 7, 31), 800)

      calcul = described_class.new(account)

      expect(calcul.poste("charges")).to be_nil
      expect(calcul.poste("n-importe-quoi")).to be_nil
    end
  end
end
