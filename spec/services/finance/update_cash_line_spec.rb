require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #243, phase 2 — corriger ou retirer une ligne de caisse. Une ligne
# comptabilisée se dé-passe, se corrige et se repasse : la contre-passation
# reste au grand livre.
RSpec.describe Finance::UpdateCashLine do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:caisse_compte) { build_general_account(code: "570000", name: "Caisse") }
  let(:recettes) { build_general_account(code: "700300", name: "Bar", klass: 7, nature: "revenue") }
  let(:epicerie_compte) { build_general_account(code: "700310", name: "Épicerie", klass: 7, nature: "revenue") }
  let(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse du domaine", kind: "cash") }

  let(:motif_bar) do
    CashMotif.create!(label: "Bar", direction: "in", general_account: recettes,
                      legal_entity: entity, position: 1)
  end
  let(:motif_epicerie) do
    CashMotif.create!(label: "Épicerie", direction: "in", general_account: epicerie_compte,
                      legal_entity: entity, position: 2)
  end

  let(:entry) do
    Finance::RecordCashLine.new(cash_account: caisse, motif: motif_bar,
                                entry_date: Date.new(2026, 6, 12), label: "Recette du bar",
                                amount_cents: 13_000).run!
  end

  it "corrige le montant et le motif, et laisse UNE seule écriture vivante" do
    described_class.new(cash_entry: entry).update!(
      motif: motif_epicerie, entry_date: Date.new(2026, 6, 13), label: "Recette de l'épicerie",
      amount_cents: 9_000, notes: "corrigé"
    )

    entry.reload
    expect(entry.amount_cents).to eq(9_000)
    expect(entry.cash_motif).to eq(motif_epicerie)
    expect(entry.entry_date).to eq(Date.new(2026, 6, 13))
    expect(entry.cash_allocations.sole.general_account).to eq(epicerie_compte)
    expect(entry.status).to eq("allocated")

    # Une seule écriture rattachée à la ligne — l'ancienne et sa contre-passation
    # restent au grand livre, détachées.
    expect(JournalEntry.where(source: entry).count).to eq(1)
    expect(entry.journal_entry.journal_lines.sum(:debit_cents)).to eq(9_000)
  end

  it "retire une ligne avec son motif, sans jamais la détruire" do
    described_class.new(cash_entry: entry).exclude!("saisie en double")

    entry.reload
    expect(entry.status).to eq("excluded")
    expect(entry.excluded_reason).to eq("saisie en double")
    expect(CashEntry.where(id: entry.id)).to exist
    expect(JournalEntry.where(source: entry)).to be_empty
  end

  it "refuse un retrait sans motif" do
    expect { described_class.new(cash_entry: entry).exclude!(" ") }.to raise_error(ArgumentError)
    expect(entry.reload.status).to eq("allocated")
  end

  it "laisse une ligne d'un mois arrêté en lecture seule" do
    entry
    MonthClosing.create!(period_month: Date.new(2026, 6, 1), closed_at: Time.current)

    expect {
      described_class.new(cash_entry: entry).update!(motif: motif_bar, entry_date: Date.new(2026, 6, 12),
                                                     label: "X", amount_cents: 100)
    }.to raise_error(described_class::MonthClosed)
    expect(entry.reload.amount_cents).to eq(13_000)
  end

  it "refuse de déplacer une ligne DANS un mois arrêté" do
    entry
    MonthClosing.create!(period_month: Date.new(2026, 5, 1), closed_at: Time.current)

    expect {
      described_class.new(cash_entry: entry).update!(motif: motif_bar, entry_date: Date.new(2026, 5, 20),
                                                     label: "X", amount_cents: 13_000)
    }.to raise_error(described_class::MonthClosed)
    expect(entry.reload.entry_date).to eq(Date.new(2026, 6, 12))
  end
end
