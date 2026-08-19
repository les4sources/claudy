require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# L'écran « À affecter » et son compteur : le seul indicateur qui dit, en un
# coup d'œil, si la comptabilité du mois est à jour. Ce que ces specs gardent,
# c'est qu'il puisse vraiment tomber à zéro.
RSpec.describe "Finances > Trésorerie", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let!(:revenue) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let!(:cash_account) { build_cash_account(entity, bank_account) }
  let!(:accueil) { Team.create!(name: "Pôle Accueil", kind: "economic") }

  before { sign_in user }

  it "crée une ligne de trésorerie à la main" do
    expect {
      post finance_cash_entries_path,
           params: { cash_entry: { cash_account_id: cash_account.id, entry_date: "2026-06-15",
                                   amount: "1300,00", label: "Virement groupe Dupont" } }
    }.to change { CashEntry.count }.by(1)

    expect(CashEntry.last.amount_cents).to eq(130_000)
  end

  # Issue #202 — l'écran faisait, pour CHAQUE ligne en attente, un rapprochement
  # de séjour à plus d'une seconde. À 10 133 lignes reprises, il demandait plus de
  # trois heures et tombait en timeout. Tout le travail est désormais borné à la
  # page affichée ; seul le compteur reste global.
  describe "avec plus d'une page de lignes en attente" do
    before { 30.times { |n| build_cash_entry(cash_account, amount_cents: 1_000 + n) } }

    it "annonce le TOTAL en attente, pas la taille de la page" do
      get finance_unallocated_cash_entries_path

      expect(response.body).to include("30 ligne(s) en attente")
      expect(response.body).to include("page 1 sur 2")
    end

    it "n'affiche qu'une page de lignes" do
      get finance_unallocated_cash_entries_path

      # Les montants sont tous distincts (10,00 à 10,29) : on compte combien
      # apparaissent réellement dans la page.
      montants = CashEntry.pending.pluck(:amount_cents).map { |c| format("%.2f", c / 100.0).tr(".", ",") }
      affiches = montants.count { |m| response.body.include?(m) }

      expect(affiches).to eq(25)
    end

    # Le coût par ligne est ce qui faisait tomber l'écran : il ne doit s'appliquer
    # qu'aux lignes visibles.
    it "ne crée pas de suggestion pour les lignes hors page" do
      expect { get finance_unallocated_cash_entries_path }
        .to change { AllocationSuggestion.count }.by_at_most(25)
    end

    it "supporte une page au-delà de la dernière" do
      get finance_unallocated_cash_entries_path, params: { page: 99 }

      expect(response).to have_http_status(:ok)
    end
  end


  describe "l'écran à affecter" do
    let!(:entry) { build_cash_entry(cash_account, amount_cents: 130_000) }

    it "montre ce qui reste et rien d'autre" do
      get finance_unallocated_cash_entries_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Virement client")
    end

    # Le geste complet : affecter le solde d'une ligne la comptabilise dans la
    # foulée. Demander un second clic pour une action qui n'a plus de décision à
    # prendre, c'est la meilleure façon de laisser des lignes en plan.
    it "affecte, comptabilise et vide le compteur" do
      post finance_cash_entry_allocations_path(entry),
           params: { cash_allocation: { general_account_id: revenue.id, team_id: accueil.id,
                                        legal_entity_id: entity.id, amount: "1300,00" } }

      expect(entry.reload.status).to eq("allocated")
      expect(entry.journal_entry).to be_present

      get finance_unallocated_cash_entries_path
      expect(response.body).to include("Rien à affecter")
    end

    it "annonce ce qui reste après une affectation partielle" do
      post finance_cash_entry_allocations_path(entry),
           params: { cash_allocation: { general_account_id: revenue.id, legal_entity_id: entity.id,
                                        amount: "800,00" } }

      expect(entry.reload.status).to eq("pending")
      expect(entry.remaining_cents).to eq(50_000)
      follow_redirect!
      expect(response.body).to include("reste")
    end
  end

  describe "la passation" do
    let!(:entry) do
      e = build_cash_entry(cash_account, amount_cents: 60_000)
      allocate(e, account: revenue, amount_cents: 60_000, entity: entity)
      e
    end

    it "annule une passation en contre-passant" do
      Accounting::PostCashEntry.new(cash_entry: entry).run!

      expect {
        post unpost_finance_cash_entry_path(entry)
      }.to change { JournalEntry.count }.by(1)

      expect(entry.reload.status).to eq("pending")
    end
  end

  describe "l'exclusion" do
    let!(:entry) { build_cash_entry(cash_account) }

    it "exige un motif" do
      post exclude_finance_cash_entry_path(entry), params: { reason: "" }

      expect(entry.reload.status).to eq("pending")
    end

    it "exclut avec son motif" do
      post exclude_finance_cash_entry_path(entry), params: { reason: "Doublon d'import" }

      expect(entry.reload.status).to eq("excluded")
      expect(entry.excluded_reason).to eq("Doublon d'import")
    end
  end

  describe "la balance analytique" do
    it "montre la part non affectée à un pôle plutôt que de la répartir" do
      entry = build_cash_entry(cash_account, amount_cents: 100_000)
      allocate(entry, account: revenue, amount_cents: 60_000, entity: entity, team: accueil)
      allocate(entry, account: revenue, amount_cents: 40_000, entity: entity)
      Accounting::PostCashEntry.new(cash_entry: entry).run!

      get finance_analytic_balance_path(from: "2026-01-01", to: "2026-12-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pôle Accueil")
      expect(response.body).to include("non affecté")
    end
  end
end
