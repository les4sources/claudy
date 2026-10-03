require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #288, phase 4 — chercher et filtrer dans la file « À affecter ».
RSpec.describe Finance::QueueFilter do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:banque) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:caisse) do
    CashAccount.create!(name: "Caisse bar", kind: "cash", legal_entity: entity,
                        general_account: build_general_account(code: "570000", name: "Caisse"))
  end

  def ligne(compte = banque, montant: 10_000, date: Date.new(2026, 6, 15), communication: nil, contrepartie: nil)
    build_cash_entry(compte, amount_cents: montant, entry_date: date).tap do |entry|
      entry.update!(communication: communication, counterparty_name: contrepartie)
    end
  end

  def ids(params) = described_class.new(params).scope.pluck(:id)

  it "rend toute la file sans filtre, et seulement les lignes en attente" do
    a = ligne
    b = ligne(caisse)
    b.update_column(:status, "allocated")

    expect(ids({})).to eq([a.id])
    expect(described_class.new({})).not_to be_active
  end

  it "cherche dans l'expéditeur et la communication, sans casse ni accents" do
    bar = ligne(communication: "Bar ÉPICERIE juin")
    nom = ligne(contrepartie: "Hélène Dupont")
    autre = ligne(communication: "Loyer")

    expect(ids(q: "epicerie")).to eq([bar.id])
    expect(ids(q: "HELENE")).to eq([nom.id])
    expect(ids(q: "  loyer ")).to eq([autre.id])
  end

  it "restreint à un compte de trésorerie" do
    ligne
    du_bar = ligne(caisse)

    expect(ids(cash_account_id: caisse.id)).to eq([du_bar.id])
  end

  it "restreint à une période, bornes comprises" do
    ligne(date: Date.new(2026, 5, 31))
    juin = ligne(date: Date.new(2026, 6, 1))
    fin = ligne(date: Date.new(2026, 6, 30))
    ligne(date: Date.new(2026, 7, 1))

    expect(ids(from: "2026-06-01", to: "2026-06-30")).to contain_exactly(juin.id, fin.id)
  end

  it "laisse ouverte une borne de période absente ou illisible" do
    vieux = ligne(date: Date.new(2020, 1, 1))
    recent = ligne(date: Date.new(2026, 6, 1))

    expect(ids(from: "2026-01-01")).to eq([recent.id])
    expect(ids(to: "pas une date")).to contain_exactly(vieux.id, recent.id)
  end

  it "sépare les entrées des sorties" do
    entree = ligne(montant: 5_000)
    sortie = ligne(montant: -5_000)

    expect(ids(sens: "in")).to eq([entree.id])
    expect(ids(sens: "out")).to eq([sortie.id])
    expect(ids(sens: "licorne")).to contain_exactly(entree.id, sortie.id)
  end

  it "filtre une fourchette de montant en valeur absolue" do
    petit = ligne(montant: -1_250)
    moyen = ligne(montant: 4_000)
    gros = ligne(montant: 90_000)

    expect(ids(min: "10", max: "50,00")).to contain_exactly(petit.id, moyen.id)
    expect(ids(max: "12,50")).to eq([petit.id])
    expect(ids(min: "-40")).to contain_exactly(moyen.id, gros.id)
    expect(ids(min: "beaucoup")).to contain_exactly(petit.id, moyen.id, gros.id)
  end

  it "combine les filtres" do
    cible = ligne(caisse, montant: 800, communication: "bar")
    ligne(caisse, montant: 80_000, communication: "bar")
    ligne(montant: 800, communication: "bar")

    expect(ids(q: "bar", cash_account_id: caisse.id, max: "10")).to eq([cible.id])
  end

  it "décrit chaque filtre actif, et sait l'enlever seul" do
    filtre = described_class.new(q: "bar", cash_account_id: caisse.id, sens: "out", min: "5", from: "2026-06-01")

    expect(filtre).to be_active
    expect(filtre.chips.map { |c| c[:key] }).to eq(%i[q cash_account_id from sens min])
    expect(filtre.chips.map { |c| c[:label] }).to include("« bar »", "Caisse bar", "Sorties", "≥ 5,00 €")
    expect(filtre.to_params(except: :q)).to eq(cash_account_id: caisse.id, from: "2026-06-01", sens: "out", min: "5,00")
  end
end
