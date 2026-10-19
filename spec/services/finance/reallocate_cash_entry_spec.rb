require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Modifier la ventilation d'une ligne déjà affectée (Michael, 2026-10-19) : un
# geste, tout ou rien, et une ligne comptabilisée contre-passée puis repassée.
RSpec.describe Finance::ReallocateCashEntry do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:cash_account) { build_cash_account(entity, bank_account) }
  let(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let(:bar) { build_general_account(code: "700100", name: "Ventes bar", klass: 7, nature: "revenue") }
  let(:accueil) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let(:cuisine) { Team.create!(name: "Pôle Cuisine", kind: "economic") }
  let(:entry) { build_cash_entry(cash_account, amount_cents: 30_000) }
  let!(:premiere) { allocate(entry, account: hebergement, amount_cents: 30_000, entity: entity, team: accueil) }

  def part(account, cents, team: nil, id: nil)
    { id: id, general_account_id: account.id, team_id: team&.id, legal_entity_id: entity.id, amount_cents: cents }
  end

  def reventiler(*parts) = described_class.new(cash_entry: entry, parts: parts, whodunnit: "compta@les4sources.be").run!

  def lignes_au_grand_livre(compte)
    JournalLine.where(general_account: compte)
              .sum("credit_cents - debit_cents")
  end

  context "quand la ligne est comptabilisée" do
    before { Accounting::PostCashEntry.new(cash_entry: entry).run! }

    it "contre-passe l'ancienne écriture et comptabilise la nouvelle ventilation" do
      resultat = reventiler(part(hebergement, 20_000, team: accueil, id: premiere.id), part(bar, 10_000, team: cuisine))

      expect(resultat).to have_attributes(changed: true, was_posted: true, posted: true)
      expect(entry.reload).to be_posted
      expect(entry.cash_allocations.map { |a| [a.general_account, a.team, a.amount_cents] })
        .to contain_exactly([hebergement, accueil, 20_000], [bar, cuisine, 10_000])
      # La part existante est modifiée en place, pas recréée.
      expect(entry.cash_allocations.find_by(general_account: hebergement).id).to eq(premiere.id)
      # Au grand livre : l'ancienne écriture, sa contre-passation, la nouvelle.
      expect(lignes_au_grand_livre(hebergement)).to eq(20_000)
      expect(lignes_au_grand_livre(bar)).to eq(10_000)
    end

    it "ne contre-passe rien quand la ventilation n'a pas changé" do
      expect do
        resultat = reventiler(part(hebergement, 30_000, team: accueil, id: premiere.id))
        expect(resultat.changed).to be(false)
      end.not_to change(JournalEntry, :count)
    end

    it "ne touche à rien quand une part est refusée, pas même à la passation" do
      expect do
        expect { reventiler(part(hebergement, 20_000, id: premiere.id), part(bar, -10_000)) }
          .to raise_error(described_class::Refused, /Part 2 : .*sens contraire/)
      end.not_to change(JournalEntry, :count)

      expect(entry.reload).to be_posted
      expect(premiere.reload.amount_cents).to eq(30_000)
    end

    it "refuse des parts qui dépassent la ligne" do
      expect { reventiler(part(hebergement, 20_000, id: premiere.id), part(bar, 20_000)) }
        .to raise_error(described_class::Refused, /Les 2 parts font 400 €, la ligne fait 300 €/)
      expect(entry.reload).to be_posted
    end

    it "laisse la ligne à affecter quand les nouvelles parts ne la couvrent plus" do
      resultat = reventiler(part(hebergement, 10_000, id: premiere.id))

      expect(resultat).to have_attributes(posted: false, remaining_cents: 20_000)
      expect(entry.reload.status).to eq("pending")
      expect(lignes_au_grand_livre(hebergement)).to eq(0)
    end

    it "refuse quand le mois est arrêté" do
      MonthClosing.create!(period_month: entry.entry_date, closed_at: Time.current, closed_by: "compta")

      expect { reventiler(part(bar, 30_000, id: premiere.id)) }
        .to raise_error(described_class::Refused, /est arrêté/)
    end
  end

  it "fait passer une part de 300 € à 200 € + 100 € sans buter sur le plafond de la ligne" do
    deuxieme_ligne = build_cash_entry(cash_account, amount_cents: 30_000)
    a = allocate(deuxieme_ligne, account: hebergement, amount_cents: 10_000, entity: entity)
    b = allocate(deuxieme_ligne, account: bar, amount_cents: 20_000, entity: entity)

    described_class.new(cash_entry: deuxieme_ligne, parts: [part(hebergement, 25_000, id: a.id), part(bar, 5_000, id: b.id)]).run!

    expect(deuxieme_ligne.cash_allocations.reload.map(&:amount_cents)).to contain_exactly(25_000, 5_000)
    expect(deuxieme_ligne.reload).to be_posted
  end

  it "garde la pièce qu'une part rapproche" do
    premiere.update_columns(document_type: "Stay", document_id: 4242)

    reventiler(part(hebergement, 30_000, team: cuisine, id: premiere.id))

    expect(premiere.reload).to have_attributes(document_type: "Stay", document_id: 4242, team_id: cuisine.id)
  end

  it "refuse une part qui appartient à une autre ligne" do
    autre = build_cash_entry(cash_account, amount_cents: 5_000)
    etrangere = allocate(autre, account: bar, amount_cents: 5_000, entity: entity)

    expect { reventiler(part(bar, 5_000, id: etrangere.id)) }
      .to raise_error(described_class::Refused, /n'appartient pas à cette ligne/)
  end
end
