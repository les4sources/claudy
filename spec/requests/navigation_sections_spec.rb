require "rails_helper"

# La scission Finances / Comptabilité (Michael, 2026-08-19).
#
# Ce que ces specs gardent, c'est la FRONTIÈRE. Un écran de comptabilité
# générale qui réapparaît dans la barre des sourciers ne casse rien : il se
# contente de rendre l'application illisible pour quelqu'un qui venait lire sa
# consommation de bar. C'est exactement le genre de régression qu'on ne voit
# pas passer — d'où le verrou ici plutôt qu'à l'œil.
RSpec.describe "Sections de navigation", type: :request do
  let(:user) { User.create!(email: "nav@les4sources.be", password: "password123") }

  before { sign_in user }

  # Les libellés qui n'appartiennent qu'à une seule des deux barres.
  SOURCIER = ["Fiches papier", "Décomptes", "Charges récurrentes"].freeze
  COMPTABLE = ["Grand livre", "Contrôle croisé", "Balance", "CODA"].freeze

  describe "la section Finances" do
    it "ne montre que les onglets du quotidien d'un sourcier" do
      get finance_accounts_path

      expect(response).to have_http_status(:ok)
      SOURCIER.each { |onglet| expect(response.body).to include(onglet) }
      COMPTABLE.each { |onglet| expect(response.body).not_to include(">#{onglet}<") }
    end

    it "garde les décomptes chez les sourciers" do
      get finance_statements_path

      expect(response.body).to include("Fiches papier")
      expect(response.body).not_to include(">Grand livre<")
    end
  end

  describe "la section Comptabilité" do
    it "porte les écrans de tenue des journaux, et pas ceux des sourciers" do
      get finance_accounting_path

      expect(response).to have_http_status(:ok)
      COMPTABLE.each { |onglet| expect(response.body).to include(onglet) }
      SOURCIER.each { |onglet| expect(response.body).not_to include(">#{onglet}<") }
    end

    # La trésorerie est l'écran le plus fréquenté de la section : si un seul
    # contrôleur devait retomber du mauvais côté, ce serait visible ici.
    it "vaut pour la trésorerie comme pour le tableau de bord" do
      get finance_cash_entries_path

      expect(response.body).to include("Grand livre")
      expect(response.body).not_to include(">Décomptes<")
    end
  end

  # Les deux entrées primaires coexistent : c'est ce qui rend la comptabilité
  # atteignable maintenant qu'elle n'est plus un onglet de Finances.
  it "propose les deux entrées primaires depuis n'importe quel écran" do
    get finance_accounts_path

    expect(response.body).to include(">Finances<").and include(">Comptabilité<")
  end
end

# Le navbar dit ce que chaque barre CONTIENT ; les socles disent quelle barre
# s'allume sur quel écran. Les specs ci-dessus ne couvrent que quatre écrans :
# ce recensement-ci couvre les vingt-quatre, et oblige tout nouveau contrôleur
# à choisir son camp explicitement plutôt qu'à hériter du camp par défaut.
RSpec.describe "Appartenance des contrôleurs Finance::", type: :model do
  # La comptabilité générale, écran par écran. Ajouter un contrôleur ici est
  # une décision : « la trésorière, pas les habitants ».
  COMPTABILITE = %w[
    accounting allocation_rules allocation_suggestions analytic_balance
    cash_allocations cash_entries coda_imports collection_cost cross_check
    fiscal_years general_accounts ledger legal_entities monthly_close
    trial_balance
  ].freeze

  before { Rails.application.eager_load! }

  def controleurs
    Finance.constants.map { |c| Finance.const_get(c) }
           .select { |k| k.is_a?(Class) && k < ActionController::Base }
           .reject { |k| k.name.end_with?("BaseController") }
  end

  it "range chaque écran de comptabilité sous le socle Comptabilité" do
    attendus = COMPTABILITE.map { |n| "Finance::#{n.camelize}Controller" }.sort
    classes = controleurs.select { |k| k < Finance::AccountingBaseController }

    expect(classes.map(&:name).sort).to eq(attendus)
  end

  it "laisse tous les autres écrans aux sourciers" do
    autres = controleurs.reject { |k| k < Finance::AccountingBaseController }

    expect(autres).to all(be < Finance::BaseController)
    expect(autres.map(&:name)).to include("Finance::AccountsController",
                                          "Finance::StatementsController",
                                          "Finance::PaperSheetsController")
  end
end
