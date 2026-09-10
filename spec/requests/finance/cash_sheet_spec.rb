require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #243, phase 2 — la feuille de caisse mensuelle.
RSpec.describe "Comptabilité > Caisse — la feuille du mois", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "caisse@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:caisse_compte) { build_general_account(code: "570000", name: "Caisse") }
  let(:recettes) { build_general_account(code: "700300", name: "Bar", klass: 7, nature: "revenue") }
  let(:charges) { build_general_account(code: "610000", name: "Services", klass: 6, nature: "expense") }
  let!(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse du domaine", kind: "cash") }
  let!(:motif_bar) do
    CashMotif.create!(label: "Bar", direction: "in", general_account: recettes,
                      legal_entity: entity, position: 1)
  end
  let!(:motif_menage) do
    CashMotif.create!(label: "Volontariat – nettoyage", direction: "out", general_account: charges,
                      legal_entity: entity, position: 2)
  end
  let(:juin) { Date.new(2026, 6, 1) }

  before { sign_in user }

  def record(motif:, amount_cents:, day:, label: "Ligne")
    Finance::RecordCashLine.new(cash_account: caisse, motif: motif, entry_date: juin + day,
                                label: label, amount_cents: amount_cents).run!
  end

  describe "GET /finance/cash" do
    it "affiche le mois, ses lignes et les deux soldes" do
      record(motif: motif_bar, amount_cents: 13_000, day: 4, label: "Recette du bar")
      record(motif: motif_menage, amount_cents: 4_500, day: 9, label: "Chèques ALE")

      get finance_cash_sheet_path(month: "2026-06")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Recette du bar", "Chèques ALE")
      expect(response.body).to include("Solde d'ouverture", "Solde de clôture")
      expect(response.body).to include("subnav-accounting")
      # 130 € encaissés − 45 € sortis = 85 € de clôture, sur une ouverture nulle.
      expect(response.body).to include("85,00")
    end

    it "part du solde COMPTABLE de la caisse, pas de la somme de ses lignes" do
      # Une écriture antérieure au mois : la reprise d'historique, par exemple.
      post_simple_entry(entity: entity, debit_account: caisse_compte, credit_account: recettes,
                        amount_cents: 50_000, entry_date: Date.new(2026, 5, 20), journal: "cash")

      get finance_cash_sheet_path(month: "2026-06")

      expect(response.body).to include("500,00")
    end

    it "prend le mois courant par défaut et propose les mois voisins" do
      get finance_cash_sheet_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.l(Date.current, format: "%B %Y"))
      expect(response.body).to include("month=#{(Date.current - 1.month).strftime('%Y-%m')}")
      expect(response.body).to include("month=#{(Date.current + 1.month).strftime('%Y-%m')}")
    end

    # La note de Michael du 2026-09-08 : la production tient sa caisse dans
    # « Caisse du domaine », et un seed y avait créé une « Caisse centrale »
    # vide, depuis désactivée. Viser un nom écrirait dans la mauvaise.
    it "vise la caisse ACTIVE, jamais un nom en dur" do
      desactivee = build_cash_account(entity, build_general_account(code: "570100", name: "Caisse 2"),
                                      name: "Caisse centrale", kind: "cash")
      desactivee.update!(active: false)
      record(motif: motif_bar, amount_cents: 13_000, day: 4, label: "Recette du domaine")

      get finance_cash_sheet_path(month: "2026-06")

      expect(response.body).to include("Recette du domaine")
      # Une seule caisse active : pas de sélecteur de compte.
      expect(response.body).not_to include("Caisse centrale")
    end

    it "le dit quand aucune caisse active n'existe" do
      caisse.update!(active: false)

      get finance_cash_sheet_path

      expect(response.body).to include("Aucune caisse active")
    end

    it "passe la feuille en lecture seule quand le mois est arrêté" do
      MonthClosing.create!(period_month: juin, closed_at: Time.current)

      get finance_cash_sheet_path(month: "2026-06")

      expect(response.body).to include("Mois arrêté")
      expect(response.body).not_to include("cash_line[cash_motif_id]")
    end
  end

  describe "POST /finance/cash/lines" do
    def line_params(overrides = {})
      { month: "2026-06", cash_account_id: caisse.id,
        cash_line: { entry_date: "2026-06-12", label: "Recette du bar",
                     cash_motif_id: motif_bar.id, amount: "130,00",
                     notes: "Soirée du samedi" }.merge(overrides) }
    end

    it "crée la ligne, l'affecte et la comptabilise en un seul geste" do
      expect { post finance_cash_sheet_lines_path, params: line_params }
        .to change(CashEntry, :count).by(1)

      entry = CashEntry.last
      expect(entry.amount_cents).to eq(13_000)
      expect(entry.status).to eq("allocated")
      expect(entry.cash_allocations.sole.general_account).to eq(recettes)
      expect(entry.journal_entry).to be_present
    end

    it "répond en Turbo Stream avec la feuille redessinée" do
      post finance_cash_sheet_lines_path, params: line_params,
                                          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="cash-sheet"')
      expect(response.body).to include("Recette du bar")
    end

    it "refuse sans motif et le dit, sans rien écrire" do
      expect { post finance_cash_sheet_lines_path, params: line_params(cash_motif_id: nil) }
        .not_to change(CashEntry, :count)

      follow_redirect!
      expect(response.body).to include("Choisis un motif")
    end
  end

  describe "corriger et retirer une ligne" do
    let!(:entry) { record(motif: motif_bar, amount_cents: 13_000, day: 11, label: "Recette du bar") }

    it "corrige la ligne et repasse son écriture" do
      patch finance_cash_sheet_line_path(entry),
            params: { month: "2026-06", cash_account_id: caisse.id,
                      cash_line: { entry_date: "2026-06-12", label: "Recette corrigée",
                                   cash_motif_id: motif_bar.id, amount: "90,00" } }

      expect(entry.reload.amount_cents).to eq(9_000)
      expect(entry.label).to eq("Recette corrigée")
      expect(JournalEntry.where(source: entry).count).to eq(1)
    end

    it "retire la ligne avec son motif, sans la détruire" do
      expect {
        post finance_exclude_cash_sheet_line_path(entry),
             params: { month: "2026-06", cash_account_id: caisse.id, reason: "saisie en double" }
      }.not_to change(CashEntry.with_deleted { CashEntry.unscoped.count }, :itself)

      expect(entry.reload.status).to eq("excluded")

      get finance_cash_sheet_path(month: "2026-06")
      expect(response.body).to include("Lignes retirées, et pourquoi", "saisie en double")
    end
  end
end
