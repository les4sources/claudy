require "rails_helper"

# Epic #240, phase 1 — l'écran des tiers. Jusqu'ici les 269 tiers de la reprise
# Winbooks vivaient sans aucun écran : ni correction, ni IBAN, ni n° de TVA.
RSpec.describe "Comptabilité — Tiers", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let!(:supplier) { ThirdParty.create!(name: "Antargaz Belgium", kind: "supplier") }
  let!(:client) { ThirdParty.create!(name: "Groupe Dupont", kind: "customer") }

  before { sign_in user }

  describe "la liste" do
    it "affiche les tiers actifs avec leur code" do
      get finance_third_parties_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Antargaz Belgium")
      expect(response.body).to include("ANTARGAZBE")
      expect(response.body).to include("Groupe Dupont")
    end

    it "cherche par nom" do
      get finance_third_parties_path(q: "Antargaz")

      expect(response.body).to include("Antargaz Belgium")
      expect(response.body).not_to include("Groupe Dupont")
    end

    it "cherche par code" do
      get finance_third_parties_path(q: "GROUPEDUPO")

      expect(response.body).to include("Groupe Dupont")
      expect(response.body).not_to include("Antargaz Belgium")
    end

    it "filtre par type" do
      get finance_third_parties_path(kind: "customer")

      expect(response.body).to include("Groupe Dupont")
      expect(response.body).not_to include("Antargaz Belgium")
    end

    it "masque les inactifs, sauf demande explicite" do
      supplier.update!(active: false)

      get finance_third_parties_path
      expect(response.body).not_to include("Antargaz Belgium")

      get finance_third_parties_path(active: "all")
      expect(response.body).to include("Antargaz Belgium")
    end

    it "signale un tiers sans numéro de TVA" do
      get finance_third_parties_path

      expect(response.body).to include("Pas de n° de TVA")
    end
  end

  describe "les formulaires" do
    # Une vue qui ne se rend jamais en spec casse au navigateur : le `new` de
    # cet écran a d'abord planté sur un `Customer#full_name` inexistant.
    it "rend le formulaire de création" do
      get new_finance_third_party_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nouveau tiers")
      expect(response.body).to include("N° de TVA")
    end

    it "rend le formulaire d'édition" do
      get edit_finance_third_party_path(supplier)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ANTARGAZBE")
    end

    it "propose les clients et les membres, et affiche le rattachement dans la liste" do
      customer = Customer.create!(first_name: "Ana", last_name: "Dupont", email: "ana@example.com")
      client.update!(customer: customer)

      get new_finance_third_party_path
      expect(response.body).to include(customer.name)

      get finance_third_parties_path
      expect(response.body).to include("Client : #{customer.name}")
    end
  end

  describe "la création" do
    it "dérive le code du nom" do
      expect {
        post finance_third_parties_path,
             params: { third_party: { name: "Électrabel Wallonie", kind: "supplier" } }
      }.to change(ThirdParty, :count).by(1)

      expect(ThirdParty.order(:id).last.code).to eq("ELECTRABEL")
      expect(response).to redirect_to(finance_third_parties_path)
    end

    it "évite la collision de code entre deux noms proches" do
      ThirdParty.create!(name: "Électrabel Wallonie", kind: "supplier")

      post finance_third_parties_path,
           params: { third_party: { name: "Electrabel Bruxelles", kind: "supplier" } }

      expect(ThirdParty.order(:id).last.code).to eq("ELECTRABE2")
    end

    it "refuse un IBAN invalide" do
      expect {
        post finance_third_parties_path,
             params: { third_party: { name: "Faux compte", kind: "supplier", iban: "BE00 0000" } }
      }.not_to change(ThirdParty, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "la modification" do
    it "enregistre IBAN, TVA et email" do
      patch finance_third_party_path(supplier),
            params: { third_party: { name: supplier.name, kind: "supplier",
                                     iban: "BE68 5390 0754 7034",
                                     vat_number: "BE0123.456.789",
                                     email: "compta@antargaz.be" } }

      supplier.reload
      expect(supplier.iban).to eq("BE68539007547034")
      expect(supplier.vat_number).to eq("BE0123.456.789")
      expect(supplier.email).to eq("compta@antargaz.be")
    end

    it "n'affiche l'IBAN qu'en clair dans le formulaire, masqué ailleurs" do
      supplier.update!(iban: "BE68 5390 0754 7034")

      get finance_third_parties_path
      expect(response.body).to include("•••• 7034")
      expect(response.body).not_to include("BE68539007547034")

      get edit_finance_third_party_path(supplier)
      expect(response.body).to include("BE68539007547034")
    end
  end

  describe "la désactivation" do
    it "désactive et réactive sans jamais détruire" do
      expect {
        patch deactivate_finance_third_party_path(supplier)
      }.not_to change(ThirdParty.unscoped, :count)
      expect(supplier.reload.active).to be(false)

      patch reactivate_finance_third_party_path(supplier)
      expect(supplier.reload.active).to be(true)
    end

    it "n'expose aucune route de destruction" do
      expect { delete finance_third_party_path(supplier) }
        .to raise_error(ActionController::RoutingError)
    end
  end

  describe "ThirdParty.for_human!" do
    let(:human) { Human.create!(name: "Michael Hulet", email: "michael@les4sources.be", status: "active") }

    it "crée le tiers d'un membre, puis le retrouve" do
      created = ThirdParty.for_human!(human)

      expect(created.human).to eq(human)
      expect(created.name).to eq("Michael Hulet")
      expect(created.email).to eq("michael@les4sources.be")
      expect(ThirdParty.for_human!(human)).to eq(created)
    end
  end
end
