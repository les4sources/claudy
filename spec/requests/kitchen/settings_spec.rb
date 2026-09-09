require "rails_helper"

# Paramètres > Cuisine (epic #219, phase 2).
RSpec.describe "Paramètres > Cuisine", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen-settings@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  before { sign_in user }

  it "affiche un bloc par famille avec les humains assignables" do
    get kitchen_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Repas", "Buffets", "Apéros")
    expect(response.body).to include("Stéphanie")
    expect(response.body).to include("malau@les4sources.be")
  end

  it "enregistre l'offre, les responsables, les plafonds et les délais" do
    patch kitchen_settings_path, params: {
      kitchen: {
        repas:  { enabled: "1", default_human_id: steph.id, max_people: "30", lead_days: "10" },
        buffet: { enabled: "1", default_human_id: "", max_people: "", lead_days: "4" },
        apero:  { enabled: "0", default_human_id: "", max_people: "", lead_days: "" },
        coordinator_email: "accueil@les4sources.be"
      }
    }

    expect(response).to redirect_to(kitchen_settings_path)
    expect(Kitchen::Config.default_human("repas")).to eq(steph)
    expect(Kitchen::Config.max_people("repas")).to eq(30)
    expect(Kitchen::Config.lead_days("repas")).to eq(10)
    expect(Kitchen::Config.max_people("buffet")).to be_nil
    expect(Kitchen::Config.enabled?("apero")).to be(false)
    expect(Kitchen::Config.enabled?("buffet")).to be(true)
    expect(Kitchen::Config.coordinator_email).to eq("accueil@les4sources.be")
  end

  it "relit les valeurs enregistrées à la réouverture" do
    patch kitchen_settings_path, params: {
      kitchen: { repas: { enabled: "1", default_human_id: steph.id, max_people: "30", lead_days: "10" },
                 buffet: { enabled: "0" }, apero: { enabled: "1" }, coordinator_email: "accueil@les4sources.be" }
    }
    get kitchen_settings_path

    expect(response.body).to include("accueil@les4sources.be")
    expect(response.body).to include('value="30"')
  end

  # Le périmètre comptable de la cuisine (epic #269, phase 1) : c'est lui que
  # lira le reporting de période, et il doit s'éditer sans toucher au code.
  describe "comptes de charge de la cuisine" do
    let!(:repas) { GeneralAccount.create!(code: "600005", name: "Achats cuisine — repas") }
    let!(:buffets) { GeneralAccount.create!(code: "600006", name: "Achats cuisine — buffets et apéros") }
    let!(:autre) { GeneralAccount.create!(code: "612000", name: "Énergie") }

    it "propose les charges actives du plan comptable" do
      get kitchen_settings_path

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Comptes de charge de la cuisine")
      expect(body).to include("600005 Achats cuisine — repas", "600006 Achats cuisine — buffets et apéros")
      expect(body).to include("612000 Énergie")
    end

    it "enregistre une sélection et la relit cochée" do
      patch kitchen_settings_path, params: {
        kitchen: { coordinator_email: "accueil@les4sources.be",
                   expense_account_ids: ["", repas.id.to_s, buffets.id.to_s] }
      }

      expect(Kitchen::Config.expense_accounts).to eq([repas, buffets])

      get kitchen_settings_path
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#kitchen_expense_account_#{repas.id}")["checked"]).to be_present
      expect(page.at_css("#kitchen_expense_account_#{buffets.id}")["checked"]).to be_present
      expect(page.at_css("#kitchen_expense_account_#{autre.id}")["checked"]).to be_nil
    end

    it "accepte d'être vidé" do
      Setting.set(Kitchen::Config::EXPENSE_ACCOUNTS_KEY, "#{repas.id},#{buffets.id}")

      patch kitchen_settings_path, params: {
        kitchen: { coordinator_email: "accueil@les4sources.be", expense_account_ids: [""] }
      }

      expect(response).to redirect_to(kitchen_settings_path)
      expect(Kitchen::Config.expense_accounts).to eq([])

      get kitchen_settings_path
      expect(response).to have_http_status(:ok)
    end

    # Le réglage sert de périmètre : un identifiant qui ne désigne pas une charge
    # active s'y lirait comme un compte absent plutôt que comme une erreur.
    it "refuse ce qui n'est pas une charge active" do
      produit = GeneralAccount.create!(code: "700200", name: "Repas")

      patch kitchen_settings_path, params: {
        kitchen: { coordinator_email: "accueil@les4sources.be",
                   expense_account_ids: [repas.id.to_s, produit.id.to_s, "999999"] }
      }

      expect(Kitchen::Config.expense_accounts).to eq([repas])
    end
  end
end
