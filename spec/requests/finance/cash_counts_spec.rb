require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #243, phase 3 — l'écran de comptage, la liste et le rappel des 7 jours.
RSpec.describe "Comptabilité > Caisse — le comptage", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "caisse@les4sources.be", password: "password123") }
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

  before { sign_in user }

  def encaisse(cents, day: Date.current)
    Finance::RecordCashLine.new(cash_account: caisse, motif: motif_bar, entry_date: day,
                                label: "Recette du bar", amount_cents: cents).run!
  end

  describe "GET /finance/cash/counts/new" do
    it "montre la grille, le solde théorique et la sous-navigation" do
      encaisse(13_000)

      get new_finance_cash_count_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Billets", "Pièces")
      # Même piège qu'à l'issue #289 : le builder pose son propre libellé faute
      # de traduction, et « Counted on » se retrouve sous « Compté le ».
      expect(response.body).not_to include(">Counted on<")
      expect(response.body).to include("Solde théorique")
      expect(response.body).to include("130,00")
      # L'entrée « Caisse » de la sous-navigation reste active sur le comptage.
      expect(response.body).to include("subnav-accounting")
      expect(response.body).to match(%r{<a[^>]+bg-teal-50 font-medium[^>]+href="#{Regexp.escape(finance_cash_sheet_path)}"})
      # Les deux issues d'un écart sont dans la page, prêtes à s'afficher.
      expect(response.body).to include("Je retrouve l'origine", "Écart inexpliqué")
    end
  end

  describe "POST /finance/cash/counts" do
    before { encaisse(13_000) }

    it "valide une caisse juste et la range dans la liste" do
      expect {
        post finance_cash_counts_path,
             params: { cash_count: { counted_on: Date.current.to_s,
                                     denominations: { "50.00" => "2", "20.00" => "1", "10.00" => "1" } } }
      }.to change { CashCount.validated.count }.by(1)

      expect(response).to redirect_to(finance_cash_counts_path)
      follow_redirect!
      expect(response.body).to include("juste")
    end

    it "renvoie à la feuille du mois quand on part chercher l'origine" do
      post finance_cash_counts_path,
           params: { cash_count: { counted_on: Date.current.to_s,
                                   denominations: { "50.00" => "2" },
                                   comment: "Un retrait non noté ?", resolution: "investigate" } }

      expect(CashCount.last).to be_draft
      expect(response).to redirect_to(finance_cash_sheet_path(month: Date.current.strftime("%Y-%m"),
                                                              cash_account_id: caisse.id))
    end

    it "écrit l'ajustement quand on assume l'écart" do
      expect {
        post finance_cash_counts_path,
             params: { cash_count: { counted_on: Date.current.to_s,
                                     denominations: { "50.00" => "2" },
                                     comment: "Introuvable.", resolution: "unexplained" } }
      }.to change { CashEntry.count }.by(1)

      expect(CashCount.last.adjustment_cash_entry.amount_cents).to eq(-3_000)
    end

    it "refuse un écart sans issue et redonne le formulaire" do
      expect {
        post finance_cash_counts_path,
             params: { cash_count: { counted_on: Date.current.to_s,
                                     denominations: { "50.00" => "2" }, comment: "Il manque 30 €" } }
      }.not_to change { CashCount.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Billets")
    end

    it "refuse un écart sans commentaire" do
      expect {
        post finance_cash_counts_path,
             params: { cash_count: { counted_on: Date.current.to_s,
                                     denominations: { "50.00" => "2" }, resolution: "unexplained" } }
      }.not_to change { CashCount.count }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "retient qui a compté" do
      post finance_cash_counts_path,
           params: { cash_count: { counted_on: Date.current.to_s,
                                   denominations: { "50.00" => "2", "20.00" => "1", "10.00" => "1" } } }

      expect(CashCount.last.counted_by).to eq(user)
    end
  end

  describe "un comptage validé" do
    let!(:count) do
      encaisse(13_000)
      Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                   denominations: { "50.00" => 2 }, comment: "Introuvable.",
                                   resolution: "unexplained").run!
    end

    it "ne se rouvre pas" do
      get edit_finance_cash_count_path(count)

      expect(response).to redirect_to(finance_cash_counts_path)
    end

    it "apparaît dans la liste avec son écart, son commentaire et son écriture" do
      get finance_cash_counts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("30,00")
      expect(response.body).to include("Introuvable.")
      expect(response.body).to include("Écart inexpliqué, ajusté")
      expect(response.body).to include(finance_cash_entry_path(count.adjustment_cash_entry))
    end
  end

  describe "un brouillon" do
    let!(:brouillon) do
      encaisse(13_000)
      Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                   denominations: { "50.00" => 2 }, comment: "À chercher",
                                   resolution: "investigate").run!
    end

    it "se rouvre avec ses quantités déjà tapées" do
      get edit_finance_cash_count_path(brouillon)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Brouillon")
      expect(response.body).to include(%(value="2"))
    end

    it "se valide sur un second comptage" do
      patch finance_cash_count_path(brouillon),
            params: { cash_count: { counted_on: Date.current.to_s,
                                    denominations: { "50.00" => "2", "20.00" => "1", "10.00" => "1" } } }

      expect(brouillon.reload).to be_validated
      expect(brouillon.difference_cents).to eq(0)
      expect(response).to redirect_to(finance_cash_counts_path)
    end
  end

  describe "le rappel sur la vue d'ensemble Comptabilité" do
    it "avertit quand la caisse n'a jamais été comptée" do
      get finance_accounting_path

      expect(response.body).to include("jamais été comptée")
      expect(response.body).to include(new_finance_cash_count_path)
    end

    it "avertit au-delà de sept jours" do
      encaisse(5_000, day: 20.days.ago.to_date)
      Finance::RecordCashCount.new(cash_account: caisse, counted_on: 20.days.ago.to_date,
                                   denominations: { "50.00" => 1 }).run!

      get finance_accounting_path

      expect(response.body).to include("Dernier comptage de caisse il y a 20 jours")
    end

    it "se tait quand le comptage est récent" do
      encaisse(5_000, day: 2.days.ago.to_date)
      Finance::RecordCashCount.new(cash_account: caisse, counted_on: 2.days.ago.to_date,
                                   denominations: { "50.00" => 1 }).run!

      get finance_accounting_path

      expect(response.body).not_to include("Dernier comptage de caisse il y a")
      expect(response.body).to include("Caisse comptée il y a 2 jour(s)")
    end

    # Un brouillon n'est pas un comptage : il ne doit pas éteindre le rappel.
    it "ne compte pas un brouillon comme un comptage" do
      encaisse(5_000)
      Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                   denominations: { "20.00" => 1 }, comment: "À chercher",
                                   resolution: "investigate").run!

      get finance_accounting_path

      expect(response.body).to include("jamais été comptée")
    end
  end

  describe "la feuille de caisse" do
    it "propose de compter la caisse" do
      get finance_cash_sheet_path

      expect(response.body).to include(new_finance_cash_count_path)
      expect(response.body).to include(finance_cash_counts_path)
    end
  end
end
