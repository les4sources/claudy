require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le moment où la promesse du lot devient visible : la compta ventile un
# virement, l'écriture en partie double sort toute seule avec le bon sens de
# chaque côté, et personne n'a tapé un débit.
RSpec.describe Accounting::PostCashEntry do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let(:salles) { build_general_account(code: "700100", name: "Salles", klass: 7, nature: "revenue") }
  let(:fournisseurs) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let(:accueil) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }
  let(:cash_account) { build_cash_account(entity, bank_account) }

  # Le cas qui motive tout le lot : un virement global de 1 300 € qui couvre
  # deux natures et deux pôles, et qui atterrissait jusqu'ici sur une seule
  # ligne « location tout ».
  it "ventile un encaissement en débitant la trésorerie et créditant chaque affectation" do
    entry = build_cash_entry(cash_account, amount_cents: 130_000, label: "Virement groupe Dupont")
    allocate(entry, account: hebergement, amount_cents: 80_000, entity: entity, team: accueil)
    allocate(entry, account: salles, amount_cents: 50_000, entity: entity, team: technique)

    journal_entry = described_class.new(cash_entry: entry).run!

    expect(journal_entry.journal).to eq("bank")
    expect(journal_entry.debit_cents).to eq(130_000)
    expect(journal_entry.credit_cents).to eq(130_000)

    debit = journal_entry.journal_lines.find { |l| l.debit_cents.positive? }
    expect(debit.general_account).to eq(bank_account)

    credits = journal_entry.journal_lines.select { |l| l.credit_cents.positive? }
    expect(credits.map { |l| l.general_account }).to contain_exactly(hebergement, salles)
    expect(credits.map { |l| l.team }).to contain_exactly(accueil, technique)

    expect(entry.reload.status).to eq("allocated")
  end

  it "inverse le sens pour un décaissement" do
    entry = build_cash_entry(cash_account, amount_cents: -45_000, label: "Facture Brico")
    allocate(entry, account: fournisseurs, amount_cents: -45_000, entity: entity)

    journal_entry = described_class.new(cash_entry: entry).run!

    credit = journal_entry.journal_lines.find { |l| l.credit_cents.positive? }
    debit = journal_entry.journal_lines.find { |l| l.debit_cents.positive? }
    expect(credit.general_account).to eq(bank_account)
    expect(debit.general_account).to eq(fournisseurs)
  end

  # Le cas que la décision « l'entité porte sur l'allocation » existe pour
  # couvrir : une charge de la Société simple payée depuis le compte de la
  # Fondation. Sans les deux écritures, il faudrait ranger la charge chez la
  # mauvaise entité — ou faire disparaître la dette entre elles.
  describe "quand une allocation appartient à une autre entité" do
    let!(:autre) { build_legal_entity(name: "Société simple de test", form: "simple_company") }
    let!(:autre_exercice) { build_fiscal_year(autre) }
    let!(:courant) do
      build_general_account(code: GeneralAccount::INTER_ENTITY_CODE, name: "Compte courant inter-entités", klass: 4)
    end

    it "produit l'écriture du mouvement ET son miroir chez l'entité tierce" do
      entry = build_cash_entry(cash_account, amount_cents: -45_000, label: "Facture Brico travaux")
      allocate(entry, account: fournisseurs, amount_cents: -45_000, entity: autre)

      expect { described_class.new(cash_entry: entry).run! }.to change { JournalEntry.count }.by(2)

      mouvement = entry.reload.journal_entry
      expect(mouvement.legal_entity).to eq(entity)
      expect(mouvement.journal_lines.map { |l| l.general_account }).to contain_exactly(bank_account, courant)

      miroir = entry.journal_entries.find { |e| e.legal_entity_id == autre.id }
      expect(miroir.journal_lines.find { |l| l.debit_cents.positive? }.general_account).to eq(fournisseurs)
      expect(miroir.journal_lines.find { |l| l.credit_cents.positive? }.general_account).to eq(courant)
    end

    it "refuse de mêler plusieurs entités tierces sur une même ligne" do
      troisieme = build_legal_entity(name: "SRL de test", form: "srl")
      build_fiscal_year(troisieme)
      entry = build_cash_entry(cash_account, amount_cents: -50_000)
      allocate(entry, account: fournisseurs, amount_cents: -25_000, entity: autre)
      allocate(entry, account: fournisseurs, amount_cents: -25_000, entity: troisieme)

      expect {
        described_class.new(cash_entry: entry).run!
      }.to raise_error(described_class::TooManyEntities, /découpe-la/i)
    end
  end

  it "refuse de comptabiliser une ligne exclue" do
    entry = build_cash_entry(cash_account, amount_cents: 10_000)
    allocate(entry, account: hebergement, amount_cents: 10_000, entity: entity)
    entry.update_columns(status: "excluded", excluded_reason: "Doublon")

    expect {
      described_class.new(cash_entry: entry).run!
    }.to raise_error(described_class::NotPostable, /exclue/i)
  end

  it "refuse de comptabiliser une ligne partiellement affectée" do
    entry = build_cash_entry(cash_account, amount_cents: 130_000)
    allocate(entry, account: hebergement, amount_cents: 80_000, entity: entity)

    expect {
      described_class.new(cash_entry: entry).run!
    }.to raise_error(described_class::NotFullyAllocated, /reste/i)
  end

  it "refuse de comptabiliser deux fois" do
    entry = build_cash_entry(cash_account, amount_cents: 10_000)
    allocate(entry, account: hebergement, amount_cents: 10_000, entity: entity)
    described_class.new(cash_entry: entry).run!

    expect {
      described_class.new(cash_entry: entry.reload).run!
    }.to raise_error(described_class::AlreadyPosted)
  end
end
