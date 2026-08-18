require "rails_helper"

# Issue #155 — écrans Finances > Comptes.
RSpec.describe "Finances > Comptes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:household) { Household.create!(name: "Famille Chevêche", kind: "resident") }

  before { sign_in user }

  def create_account(attrs = {})
    MemberAccount.create!({ kind: "entity", name: "Semisto" }.merge(attrs))
  end

  describe "GET /finance/accounts" do
    it "liste les comptes avec leur solde, du plus débiteur au moins" do
      poor = create_account(name: "Low tech")
      rich = create_account(name: "Semisto")
      rich.account_entries.create!(entry_date: Date.current, amount_cents: 12_000, label: "Bar")
      poor.account_entries.create!(entry_date: Date.current, amount_cents: -500, label: "Règlement")

      get finance_accounts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Comptes courants")
      expect(response.body).to include("Semisto", "Low tech")
      expect(response.body.index("Semisto")).to be < response.body.rindex("Low tech")
    end

    it "affiche l'entrée primaire Finances et sa sous-navigation" do
      get finance_accounts_path

      expect(response.body).to include("Finances")
      expect(response.body).to include(finance_accounts_path)
    end

    it "filtre les comptes inactifs" do
      create_account(name: "Semisto")
      create_account(name: "Ancien compte", active: false)

      get finance_accounts_path
      expect(response.body).not_to include("Ancien compte")

      get finance_accounts_path(filter: "inactive")
      expect(response.body).to include("Ancien compte")
      expect(response.body).not_to include(">Semisto<")

      get finance_accounts_path(filter: "all")
      expect(response.body).to include("Ancien compte", "Semisto")
    end

    it "reste lisible quand le compte est ancré sur une personne désactivée" do
      human = Human.create!(name: "Ada Lovelace", status: "active")
      account = create_account(kind: "human", name: "Ada Lovelace", human_id: human.id)
      account.account_entries.create!(entry_date: Date.current, amount_cents: 2_400, label: "Bar")
      human.update_column(:status, "inactive")

      get finance_accounts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ada Lovelace")
      expect(response.body).to include("24,00")
    end
  end

  describe "GET /finance/accounts/:id" do
    it "affiche le grand livre, le solde et le solde d'ouverture" do
      account = create_account(opening_balance_cents: 5_000, opening_balance_on: Date.new(2024, 1, 1))
      account.account_entries.create!(entry_date: Date.new(2024, 2, 1), amount_cents: 1_250, label: "Bières")
      account.account_entries.create!(entry_date: Date.new(2024, 3, 1), amount_cents: -3_000, label: "Règlement")

      get finance_account_path(account)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bières", "Règlement")
      expect(response.body).to include("32,50")            # solde : 50 + 12,50 − 30
      # L'apostrophe est échappée en HTML.
      expect(response.body).to include("Solde d&#39;ouverture au 1 janvier 2024 : 50,00")
    end

    it "marque les écritures verrouillées et n'offre pas de suppression" do
      account = create_account
      # Un VRAI décompte : depuis #160, la colonne porte une clé étrangère.
      statement = AccountStatement.create!(member_account: account, period_month: Date.current)
      account.account_entries.create!(entry_date: Date.current, amount_cents: 1_000,
                                      label: "Verrouillée", account_statement_id: statement.id)

      get finance_account_path(account)

      expect(response.body).to include("verrouillée")
      expect(response.body).to include("🔒")
    end

    it "reste lisible pour un compte ancré sur une personne désactivée" do
      human = Human.create!(name: "Ada Lovelace", status: "active")
      account = create_account(kind: "human", name: "Ada Lovelace", human_id: human.id)
      human.update_column(:status, "inactive")

      get finance_account_path(account)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ada Lovelace")
    end
  end

  describe "création et édition" do
    it "crée un compte de ménage et lui attribue un code" do
      expect {
        post finance_accounts_path, params: {
          member_account: { kind: "household", household_id: household.id, name: "Famille Chevêche",
                            opening_balance_euros: "12,50", active: "1" }
        }
      }.to change(MemberAccount, :count).by(1)

      account = MemberAccount.last
      expect(account.code).to match(/\ASRC-\d{4}\z/)
      expect(account.opening_balance_cents).to eq(1_250)
      expect(response).to redirect_to(finance_account_path(account))
    end

    it "ignore l'ancre qui ne correspond pas au type choisi" do
      human = Human.create!(name: "Ada Lovelace", status: "active")

      post finance_accounts_path, params: {
        member_account: { kind: "entity", name: "Semisto", household_id: household.id, human_id: human.id }
      }

      account = MemberAccount.last
      expect(account.household_id).to be_nil
      expect(account.human_id).to be_nil
    end

    it "refuse un compte de ménage sans ménage" do
      expect {
        post finance_accounts_path, params: { member_account: { kind: "household", name: "Bancal" } }
      }.not_to change(MemberAccount, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "met à jour un compte" do
      account = create_account

      patch finance_account_path(account), params: {
        member_account: { kind: "entity", name: "Semisto ASBL", active: "0" }
      }

      expect(account.reload.name).to eq("Semisto ASBL")
      expect(account.active).to be(false)
    end
  end

  describe "écritures manuelles" do
    let(:account) { create_account }

    it "ajoute une écriture positive puis une négative" do
      post finance_account_entries_path(account), params: {
        account_entry: { entry_date: Date.current.to_s, label: "Bières", flow: "bar", amount: "12,50" }
      }
      post finance_account_entries_path(account), params: {
        account_entry: { entry_date: Date.current.to_s, label: "Règlement", amount: "-30" }
      }

      expect(account.reload.balance_cents).to eq(1_250 - 3_000)
    end

    it "refuse une écriture à zéro avec un message" do
      expect {
        post finance_account_entries_path(account), params: {
          account_entry: { entry_date: Date.current.to_s, label: "Vide", amount: "0" }
        }
      }.not_to change(AccountEntry, :count)

      expect(flash[:alert]).to be_present
    end

    it "supprime une écriture libre" do
      entry = account.account_entries.create!(entry_date: Date.current, amount_cents: 1_000, label: "Bar")

      delete finance_account_entry_path(account, entry)

      expect(account.reload.balance_cents).to eq(0)
      expect(flash[:notice]).to be_present
    end

    it "refuse la suppression d'une écriture verrouillée, avec un message clair" do
      statement = AccountStatement.create!(member_account: account, period_month: Date.current)
      entry = account.account_entries.create!(entry_date: Date.current, amount_cents: 1_000,
                                              label: "Bar", account_statement_id: statement.id)

      delete finance_account_entry_path(account, entry)

      expect(response).to redirect_to(finance_account_path(account))
      expect(flash[:alert]).to include("décompte émis")
      expect(account.reload.balance_cents).to eq(1_000)
    end
  end

describe "le callout des paiements dûs" do
      # La table des écritures, en bas de page, porte les mêmes libellés :
      # une assertion sur la page entière passerait sans que le callout existe.
      def callout = Nokogiri::HTML(response.body).at_css("#outstanding")&.text.to_s
  it "décompose le solde mois par mois au lieu de l'afficher nu" do
    account = create_account(name: "Béné", kind: "household", household: household)
    account.account_entries.create!(entry_date: Date.new(2026, 1, 31), amount_cents: 17_000,
                                    label: "Charges habitants", flow: "charges")
    account.account_entries.create!(entry_date: Date.new(2026, 6, 27), amount_cents: 2_500,
                                    label: "Batchcooking", flow: "meal")

    get finance_account_path(account)

    expect(callout).to include("À régler")
    expect(callout).to include("Charges habitants").and include("Batchcooking")
    expect(callout).to include("Janvier 2026").and include("Juin 2026")
    # Le total du callout est le solde : les deux nombres de la page doivent
    # tomber pareil, sinon la décomposition dit le contraire du solde.
    expect(callout).to include("195,00")
  end

  it "ne montre que ce qui reste après imputation des règlements" do
    account = create_account(name: "Béné", kind: "household", household: household)
    account.account_entries.create!(entry_date: Date.new(2026, 1, 31), amount_cents: 17_000,
                                    label: "Charges de janvier", flow: "charges")
    account.account_entries.create!(entry_date: Date.new(2026, 3, 31), amount_cents: 5_000,
                                    label: "Conso bar", flow: "bar")
    account.account_entries.create!(entry_date: Date.new(2026, 2, 5), amount_cents: -17_000,
                                    label: "Virement")

    get finance_account_path(account)

    expect(callout).to include("Conso bar")
    expect(callout).not_to include("Charges de janvier")
  end

  it "se tait quand le compte est à zéro" do
    account = create_account(name: "Semisto")

    get finance_account_path(account)

    expect(callout).not_to include("À régler")
  end

  it "annonce une avance plutôt qu'une dette quand le compte est créditeur" do
    account = create_account(name: "Semisto")
    account.account_entries.create!(entry_date: Date.current, amount_cents: -4_000, label: "Provision")

    get finance_account_path(account)

    expect(callout).to include("Rien à régler")
    expect(callout).to include("en avance sur ses consommations")
  end
end

describe "sans authentification" do
    it "redirige la liste et la fiche vers la connexion" do
      account = create_account
      sign_out user

      get finance_accounts_path
      expect(response).to redirect_to(new_user_session_path)

      get finance_account_path(account)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
