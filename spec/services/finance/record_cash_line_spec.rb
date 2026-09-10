require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #243, phase 2 — une ligne de feuille de caisse. Le motif EST
# l'affectation : la ligne naît affectée et comptabilisée.
RSpec.describe Finance::RecordCashLine do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:caisse_compte) { build_general_account(code: "570000", name: "Caisse") }
  let(:recettes) { build_general_account(code: "700300", name: "Bar et cellier", klass: 7, nature: "revenue") }
  let(:charges) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse du domaine", kind: "cash") }
  let(:pole) { Team.create!(name: "Pôle Accueil") }

  let(:motif_bar) do
    CashMotif.create!(label: "Bar", direction: "in", general_account: recettes,
                      legal_entity: entity, team: pole, position: 1)
  end
  let(:motif_menage) do
    CashMotif.create!(label: "Volontariat – nettoyage", direction: "out", general_account: charges,
                      legal_entity: entity, position: 2)
  end

  def record(motif:, amount_cents: 13_000, entry_date: Date.new(2026, 6, 12), label: "Recette du bar", notes: nil)
    described_class.new(cash_account: caisse, motif: motif, entry_date: entry_date,
                        label: label, amount_cents: amount_cents, notes: notes).run!
  end

  it "crée une ligne positive, son allocation copiée du motif, et son écriture" do
    entry = record(motif: motif_bar, notes: "Soirée du samedi")

    expect(entry.amount_cents).to eq(13_000)
    expect(entry.status).to eq("allocated")
    expect(entry.notes).to eq("Soirée du samedi")
    expect(entry.cash_motif).to eq(motif_bar)

    allocation = entry.cash_allocations.sole
    expect(allocation.general_account).to eq(recettes)
    expect(allocation.team).to eq(pole)
    expect(allocation.legal_entity).to eq(entity)
    expect(allocation.amount_cents).to eq(13_000)

    ecriture = entry.journal_entry
    expect(ecriture.journal).to eq("cash")
    expect(ecriture.journal_lines.sum(:debit_cents)).to eq(13_000)
    expect(ecriture.journal_lines.find { |l| l.debit_cents.positive? }.general_account).to eq(caisse_compte)
  end

  it "rend NÉGATIF le montant d'un motif de sortie, quel que soit le signe saisi" do
    entry = record(motif: motif_menage, amount_cents: 4_500, label: "Chèques ALE")

    expect(entry.amount_cents).to eq(-4_500)
    expect(entry.cash_allocations.sole.amount_cents).to eq(-4_500)
  end

  it "n'écrit rien quand l'affectation du motif est absente" do
    expect { described_class.new(cash_account: caisse, motif: nil, entry_date: Date.current,
                                 label: "X", amount_cents: 100).run! }
      .to raise_error(described_class::MissingMotif)
    expect(CashEntry.count).to eq(0)
  end

  it "refuse un montant nul" do
    expect { record(motif: motif_bar, amount_cents: 0) }.to raise_error(ArgumentError)
    expect(CashEntry.count).to eq(0)
  end

  it "refuse de saisir dans un mois arrêté" do
    MonthClosing.create!(period_month: Date.new(2026, 6, 1), closed_at: Time.current)

    expect { record(motif: motif_bar) }.to raise_error(described_class::MonthClosed)
    expect(CashEntry.count).to eq(0)
  end

  # Décision 4 : l'allocation est une COPIE. Réaffecter un motif l'an prochain
  # ne doit pas réécrire la caisse de cette année.
  it "ne réécrit pas une ligne passée quand le motif change ensuite" do
    entry = record(motif: motif_bar)
    motif_bar.update!(general_account: charges, team: nil)

    expect(entry.reload.cash_allocations.sole.general_account).to eq(recettes)
    expect(entry.cash_allocations.sole.team).to eq(pole)
  end
end
