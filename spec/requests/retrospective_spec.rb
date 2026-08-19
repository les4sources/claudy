require "rails_helper"

# La lecture agrégée d'un compte, et son sélecteur de période.
#
# Tous les habitants ont un accès Claudy (Michael, 2026-08-19) : la page vit
# donc derrière Devise, sans porte publique par jeton.
RSpec.describe "Lecture d'un compte", type: :request do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }
  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }

  before do
    account.account_entries.create!(entry_date: Date.current.beginning_of_month, amount_cents: 17_000,
                                    label: "Charges habitants", flow: "charges")
    account.account_entries.create!(entry_date: Date.current.beginning_of_month, amount_cents: 1_200,
                                    label: "Moinette", flow: "bar")
    sign_in user
  end

  it "montre la répartition et se laisse atteindre depuis la fiche" do
    get retrospective_finance_account_path(account)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lecture du compte")
    expect(response.body).to include("Le rythme des mois")
    expect(response.body).to include("Charges").and include("Bar")

    get finance_account_path(account)
    expect(response.body).to include(retrospective_finance_account_path(account))
  end

  it "exige d'être connecté" do
    sign_out user

    get retrospective_finance_account_path(account)

    expect(response).to redirect_to(new_user_session_path)
  end

  describe "le choix de période" do
    it "propose la fenêtre glissante et les années où le compte a bougé" do
      get retrospective_finance_account_path(account)

      expect(response.body).to include("12 derniers mois")
      expect(response.body).to include(retrospective_finance_account_path(account, periode: Date.current.year.to_s))
    end

    it "cadre sur l'année civile demandée" do
      account.account_entries.create!(entry_date: Date.new(Date.current.year - 1, 3, 15), amount_cents: 5_000,
                                      label: "Vieille conso", flow: "bar")

      get retrospective_finance_account_path(account, periode: (Date.current.year - 1).to_s)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("janvier #{Date.current.year - 1}")
      expect(response.body).to include("50,00")
      expect(response.body).not_to include("Charges habitants")
    end

    # Le paramètre vient de l'URL : une valeur bricolée ne doit pas rendre 500.
    it "retombe sur la fenêtre glissante devant une période inconnue" do
      get retrospective_finance_account_path(account, periode: "1789")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("12 derniers mois")
    end
  end

  # Une page de graphiques vides serait pire qu'une phrase : elle laisserait
  # croire à une panne.
  it "dit en une phrase qu'un compte n'a pas bougé" do
    vide = MemberAccount.create!(kind: "entity", name: "Low tech")

    get retrospective_finance_account_path(vide)

    expect(response.body).to include("Aucun mouvement")
    expect(response.body).not_to include("Le rythme des mois")
  end

  # L'accès public par jeton a été retiré : le décompte reste un mois, et rien
  # n'y renvoie vers l'historique.
  it "n'expose aucune route publique vers la lecture du compte" do
    statement = Finance::IssueStatement.new(member_account: account, month: Date.current.strftime("%Y-%m")).run!

    expect { get "/decompte/#{statement.token}/annee" }.to raise_error(ActionController::RoutingError)

    get "/decompte/#{statement.token}"
    expect(response.body).not_to include("/annee")
  end
end
