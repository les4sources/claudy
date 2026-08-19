require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les six écrans de la comptabilité. Ce que ces specs gardent surtout, c'est
# l'absence : aucun écran ne permet de saisir un débit et un crédit à la main.
RSpec.describe "Finances > Comptabilité", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank) { build_general_account(code: "550000", name: "Banque") }
  let!(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }

  before { sign_in user }

  describe "le tableau de bord" do
    it "affiche le référentiel et ses compteurs" do
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)

      get finance_accounting_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(entity.name)
      expect(response.body).to include("Plan comptable")
    end
  end

  describe "le plan comptable" do
    it "liste les comptes et filtre par classe" do
      get finance_general_accounts_path
      expect(response.body).to include("550000").and include("700000")

      get finance_general_accounts_path(klass: 7)
      expect(response.body).to include("700000")
      expect(response.body).not_to include(">550000<")
    end

    it "crée un compte" do
      expect {
        post finance_general_accounts_path,
             params: { general_account: { code: "613000", name: "Honoraires", klass: 6, nature: "expense" } }
      }.to change { GeneralAccount.count }.by(1)
    end

    it "refuse un code en double plutôt que d'échouer en silence" do
      expect {
        post finance_general_accounts_path,
             params: { general_account: { code: "550000", name: "Doublon", klass: 5, nature: "asset" } }
      }.not_to change { GeneralAccount.count }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuse de supprimer un compte qui porte des écritures" do
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)

      expect {
        delete finance_general_account_path(bank)
      }.not_to change { GeneralAccount.count }
    end
  end

  describe "les exercices" do
    it "les liste et en clôture un" do
      get finance_fiscal_years_path
      expect(response.body).to include(entity.name)

      post close_finance_fiscal_year_path(fiscal_year)
      expect(fiscal_year.reload).to be_closed
    end
  end

  describe "les entités" do
    it "les liste et en crée une" do
      get finance_legal_entities_path
      expect(response.body).to include(entity.name)

      expect {
        post finance_legal_entities_path,
             params: { legal_entity: { name: "Nouvelle SRL", form: "srl", vat_regime: "subject" } }
      }.to change { LegalEntity.count }.by(1)
    end
  end

  describe "le grand livre" do
    it "affiche les mouvements d'un compte avec son solde progressif" do
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue, amount_cents: 12_345)

      get finance_ledger_path(general_account_id: bank.id, from: "2026-01-01", to: "2026-12-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("123,45")
    end

    it "demande un compte plutôt que de tout déverser" do
      get finance_ledger_path

      expect(response.body).to include("Choisis un compte")
    end
  end

  describe "la balance" do
    it "montre l'équilibre débit / crédit" do
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue, amount_cents: 50_000)

      get finance_trial_balance_path(from: "2026-01-01", to: "2026-12-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("équilibrée")
    end
  end

  # L'anti-critère du lot : la double écriture se génère, elle ne se saisit
  # jamais. Aucun contrôleur ne doit créer une écriture.
  it "n'expose aucun chemin de saisie manuelle d'écriture" do
    controllers = Dir[Rails.root.join("app/controllers/**/*.rb")].map { |path| File.read(path) }

    expect(controllers.join).not_to match(/JournalEntry\.(new|create)/)
  end

  describe "sans authentification" do
    it "renvoie vers la connexion" do
      sign_out user

      get finance_accounting_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
  # Retirer une entité créée par erreur — le cas réel : « Marco & Vespucci »,
  # la SRL de Michael, n'a rien à faire dans la compta des 4 Sources.
  #
  # Le garde-fou n'est pas dans le bouton, il est dans le modèle : une entité
  # qui porte un exercice, un compte ou une écriture ne peut pas partir, et le
  # refus est motivé plutôt que silencieux.
  describe "supprimer une entité" do
    it "retire une entité qui ne porte rien" do
      seule = LegalEntity.create!(name: "Créée par erreur", form: "srl", vat_regime: "exempt")

      expect { delete finance_legal_entity_path(seule) }.to change(LegalEntity, :count).by(-1)
      expect(flash[:notice]).to include("supprimée")
    end

    it "refuse tant qu'un exercice y est rattaché, et le dit" do
      expect { delete finance_legal_entity_path(entity) }.not_to change(LegalEntity, :count)

      expect(flash[:alert]).to include("exercices")
    end

    it "offre le bouton sur l'écran, faute de quoi la route est injoignable" do
      get finance_legal_entities_path

      expect(response.body).to include(finance_legal_entity_path(entity))
      expect(response.body).to include("Supprimer")
    end

    # L'ordre imposé : l'exercice vide d'abord, l'entité ensuite.
    it "laisse partir l'entité une fois son exercice vide retiré" do
      delete finance_fiscal_year_path(fiscal_year)

      expect { delete finance_legal_entity_path(entity) }.to change(LegalEntity, :count).by(-1)
    end

    it "garde un exercice qui porte des écritures" do
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)

      expect { delete finance_fiscal_year_path(fiscal_year) }.not_to change(FiscalYear, :count)
      expect(flash[:alert]).to include("écritures")
    end

    # Un arrêté ne se défait pas d'un clic : le bouton n'existe pas sur un
    # exercice clôturé.
    it "ne propose pas la suppression d'un exercice clôturé" do
      fiscal_year.update!(status: "closed")

      get finance_fiscal_years_path

      expect(response.body).not_to include(%(action="#{finance_fiscal_year_path(fiscal_year)}"))
    end
  end
end
