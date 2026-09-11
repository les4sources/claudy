require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #243, phase 3 — le comptage fige l'écart et, quand on l'assume, l'écrit.
RSpec.describe Finance::RecordCashCount do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:caisse_compte) { build_general_account(code: "570000", name: "Caisse") }
  let(:recettes) { build_general_account(code: "700300", name: "Bar", klass: 7, nature: "revenue") }
  let!(:ecarts) do
    build_general_account(code: GeneralAccount::CASH_DIFFERENCE_CODE, name: "Écarts de caisse",
                          klass: 6, nature: "expense")
  end
  let!(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse du domaine", kind: "cash") }
  let!(:motif_bar) do
    CashMotif.create!(label: "Bar", direction: "in", general_account: recettes,
                      legal_entity: entity, position: 1)
  end
  let(:jour) { Date.new(2026, 6, 15) }

  def encaisse(cents, day: jour)
    Finance::RecordCashLine.new(cash_account: caisse, motif: motif_bar, entry_date: day,
                                label: "Recette du bar", amount_cents: cents).run!
  end

  def compte(grille, comment: nil, resolution: nil, count: nil, on: jour)
    described_class.new(cash_account: caisse, counted_on: on, denominations: grille,
                        comment: comment, resolution: resolution, count: count).run!
  end

  describe "une caisse qui tombe juste" do
    it "valide sans commentaire, sans issue et sans écriture" do
      encaisse(13_000)

      count = compte({ "50.00" => 2, "20.00" => 1, "10.00" => 1 })

      expect(count).to be_validated
      expect(count.counted_cents).to eq(13_000)
      expect(count.expected_cents).to eq(13_000)
      expect(count.difference_cents).to eq(0)
      expect(count.resolution).to be_nil
      expect(count.adjustment_cash_entry).to be_nil
    end
  end

  describe "un écart" do
    before { encaisse(13_000) }

    it "refuse de valider sans issue" do
      expect { compte({ "50.00" => 2 }, comment: "Il manque 30 €") }
        .to raise_error(described_class::MissingResolution)
    end

    it "refuse de valider sans commentaire" do
      expect { compte({ "50.00" => 2 }, resolution: "unexplained") }
        .to raise_error(ActiveRecord::RecordInvalid, /commentaire|obligatoire/i)
    end

    # « Je retrouve l'origine » n'écrit rien : le comptage attend la ligne
    # manquante.
    it "reste en brouillon quand on part chercher l'origine" do
      expect {
        count = compte({ "50.00" => 2 }, comment: "Un retrait non noté ?", resolution: "investigate")
        expect(count).to be_draft
        expect(count.difference_cents).to eq(-3_000)
        expect(count.adjustment_cash_entry).to be_nil
      }.not_to change { CashEntry.count }
    end

    it "écrit exactement une ligne d'ajustement quand on assume l'écart" do
      expect {
        @count = compte({ "50.00" => 2 }, comment: "Introuvable.", resolution: "unexplained")
      }.to change { CashEntry.count }.by(1)

      expect(@count).to be_validated
      expect(@count.difference_cents).to eq(-3_000)

      ajustement = @count.adjustment_cash_entry
      expect(ajustement.amount_cents).to eq(-3_000)
      expect(ajustement).to be_posted
      expect(ajustement.cash_allocations.first.general_account).to eq(ecarts)
    end

    # Une caisse en PLUS est un ajustement de sens contraire — pas un écart
    # qu'on garde pour compenser le prochain manque.
    it "écrit l'ajustement dans le bon sens quand il y a trop d'argent" do
      count = compte({ "50.00" => 2, "20.00" => 1, "10.00" => 1, "5.00" => 1 },
                     comment: "Trop plein.", resolution: "unexplained")

      expect(count.difference_cents).to eq(500)
      expect(count.adjustment_cash_entry.amount_cents).to eq(500)
    end

    it "refuse d'ajuster un mois arrêté" do
      MonthClosing.create!(period_month: jour.beginning_of_month, closed_at: Time.current)

      expect { compte({ "50.00" => 2 }, comment: "Introuvable.", resolution: "unexplained") }
        .to raise_error(Finance::RecordCashLine::MonthClosed)
    end
  end

  # Décision 3 : l'écart se fige. Une ligne qui arrive après le comptage ne doit
  # pas faire disparaître l'écart constaté.
  it "fige le solde théorique même si une ligne arrive après" do
    encaisse(13_000)
    count = compte({ "50.00" => 2 }, comment: "Introuvable.", resolution: "unexplained")

    encaisse(2_000, day: jour)

    expect(count.reload.expected_cents).to eq(13_000)
    expect(count.difference_cents).to eq(-3_000)
  end

  it "refuse de rejouer un comptage validé" do
    encaisse(13_000)
    count = compte({ "50.00" => 2, "20.00" => 1, "10.00" => 1 })

    expect { compte({ "50.00" => 1 }, count: count, comment: "Bis", resolution: "unexplained") }
      .to raise_error(described_class::AlreadyValidated)
  end

  it "reprend un brouillon et le valide" do
    encaisse(13_000)
    brouillon = compte({ "50.00" => 2 }, comment: "À chercher", resolution: "investigate")

    valide = compte({ "50.00" => 2, "20.00" => 1, "10.00" => 1 }, count: brouillon)

    expect(valide.id).to eq(brouillon.id)
    expect(valide).to be_validated
    expect(valide.difference_cents).to eq(0)
  end

  it "signale l'absence du compte des écarts plutôt que de le créer" do
    encaisse(13_000)
    ecarts.destroy

    expect { compte({ "50.00" => 2 }, comment: "Introuvable.", resolution: "unexplained") }
      .to raise_error(described_class::MissingDifferenceAccount)
  end

  it "ignore les dénominations inventées et les quantités nulles" do
    encaisse(5_000)

    count = compte({ "50.00" => 1, "3.00" => 4, "0.02" => 0 })

    expect(count.denominations).to eq({ "50.00" => 1 })
    expect(count.counted_cents).to eq(5_000)
  end
end
