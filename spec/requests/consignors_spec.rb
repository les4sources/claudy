require "rails_helper"

# Epic #248, phase 1 — écran Paramètres > Dépôt-vente.
RSpec.describe "Paramètres > Dépôt-vente", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "depot@les4sources.be", password: "password123") }
  before { sign_in user }

  def base_params(overrides = {})
    { consignor: { name: "Eline", email: "eline@example.com", commission_percent: 20,
                   settlement_mode: "invoice", starts_on: "2026-09-01", active: "1" }.merge(overrides) }
  end

  describe "GET /consignors" do
    it "liste les artisans avec leur mode, leur commission et leur statut" do
      Consignor.create!(name: "Eline", settlement_mode: "transfer",
                        iban: "BE68539007547034", commission_percent: 25)
      Consignor.create!(name: "Atelier du Bois", settlement_mode: "invoice", active: false)

      get consignors_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Eline", "Atelier du Bois")
      expect(response.body).to include("25 %")
      expect(response.body).to include("Virement des 4 Sources")
      expect(response.body).to include("artisan facture")
      expect(response.body).to include("Actif", "Inactif")
      # L'entrée vit bien dans la sous-navigation Paramètres.
      expect(response.body).to include("subnav-settings")
    end

    it "n'affiche jamais l'IBAN en entier" do
      Consignor.create!(name: "Eline", settlement_mode: "transfer", iban: "BE68539007547034")

      get consignors_path

      expect(response.body).not_to include("BE68539007547034")
      expect(response.body).to include("7034")
    end

    it "le dit quand personne n'est encore enregistré" do
      get consignors_path

      expect(response.body).to include("Aucun artisan en dépôt-vente")
    end
  end

  describe "POST /consignors" do
    it "crée l'artisan et revient à la liste" do
      expect { post consignors_path, params: base_params }.to change(Consignor, :count).by(1)

      expect(response).to redirect_to(consignors_path)
      expect(Consignor.last.name).to eq("Eline")
      expect(Consignor.last.commission_percent).to eq(20)
    end

    it "refuse un virement sans IBAN et réaffiche le formulaire" do
      expect {
        post consignors_path, params: base_params(settlement_mode: "transfer", iban: "")
      }.not_to change(Consignor, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("virement")
    end

    it "refuse un IBAN invalide" do
      post consignors_path, params: base_params(settlement_mode: "transfer", iban: "BE00000000000000")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("IBAN")
    end
  end

  describe "GET /consignors/new" do
    it "propose les membres de l'équipe avec leur nom et leur email en données" do
      Human.create!(name: "Eline Dupont", email: "eline@les4sources.be")

      get new_consignor_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-name="Eline Dupont"')
      expect(response.body).to include('data-email="eline@les4sources.be"')
      expect(response.body).to include("consignor-human")
    end
  end

  describe "PATCH /consignors/:id" do
    let!(:consignor) { Consignor.create!(name: "Eline", settlement_mode: "invoice") }

    it "met à jour la commission" do
      patch consignor_path(consignor), params: base_params(commission_percent: 30)

      expect(response).to redirect_to(consignors_path)
      expect(consignor.reload.commission_percent).to eq(30)
    end

    it "refuse une commission au-delà de 100" do
      patch consignor_path(consignor), params: base_params(commission_percent: 120)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(consignor.reload.commission_percent).to eq(20)
    end
  end

  describe "désactivation / réactivation" do
    let!(:consignor) { Consignor.create!(name: "Eline", settlement_mode: "invoice") }

    it "désactive sans détruire" do
      patch deactivate_consignor_path(consignor)

      expect(response).to redirect_to(consignors_path)
      expect(consignor.reload.active).to be(false)
      expect(Consignor.count).to eq(1)
    end

    it "réactive" do
      consignor.update!(active: false)

      patch reactivate_consignor_path(consignor)

      expect(consignor.reload.active).to be(true)
    end
  end

  it "exige une session" do
    sign_out user

    get consignors_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
