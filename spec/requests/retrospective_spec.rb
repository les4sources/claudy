require "rails_helper"

# Les douze mois d'un compte, sur les deux portes d'entrée : le jeton du
# décompte (un habitant, sans compte Claudy) et la fiche interne (nous).
#
# La page PUBLIQUE est celle qui compte : c'est elle qui fait de ce reporting
# autre chose qu'un écran d'administration de plus.
RSpec.describe "Douze mois de compte", type: :request do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  before do
    account.account_entries.create!(entry_date: Date.current.beginning_of_month, amount_cents: 17_000,
                                    label: "Charges habitants", flow: "charges")
    account.account_entries.create!(entry_date: Date.current.beginning_of_month, amount_cents: 1_200,
                                    label: "Moinette", flow: "bar")
  end

  describe "par le jeton du décompte" do
    let(:statement) { Finance::IssueStatement.new(member_account: account, month: Date.current.strftime("%Y-%m")).run! }

    it "s'ouvre sans authentification et montre la répartition" do
      get "/decompte/#{statement.token}/annee"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Douze mois de compte")
      expect(response.body).to include("Charges").and include("Bar")
      expect(response.body).to include(account.code)
    end

    it "renvoie la page d'invalidité sur un jeton inconnu, sans fuiter de compte" do
      get "/decompte/pas-un-jeton/annee"

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Chevêche")
    end

    # Sans ce lien, la page n'a aucune porte d'entrée pour un habitant : le mail
    # du décompte est le seul endroit où il reçoit une URL.
    it "est atteignable depuis le décompte du mois" do
      get "/decompte/#{statement.token}"

      expect(response.body).to include("/decompte/#{statement.token}/annee")
    end
  end

  describe "depuis la fiche du compte" do
    let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }

    before { sign_in user }

    it "rend la même page, et se laisse atteindre depuis la fiche" do
      get retrospective_finance_account_path(account)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Le rythme des mois")

      get finance_account_path(account)
      expect(response.body).to include(retrospective_finance_account_path(account))
    end

    it "exige d'être connecté" do
      sign_out user

      get retrospective_finance_account_path(account)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "un compte sans mouvement" do
    let(:vide) { MemberAccount.create!(kind: "entity", name: "Low tech") }
    let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }

    before { sign_in user }

    # Une page de graphiques vides serait pire qu'une phrase : elle laisserait
    # croire à une panne.
    it "le dit en une phrase plutôt que d'afficher des graphiques à zéro" do
      get retrospective_finance_account_path(vide)

      expect(response.body).to include("Aucun mouvement")
      expect(response.body).not_to include("Le rythme des mois")
    end
  end
end
