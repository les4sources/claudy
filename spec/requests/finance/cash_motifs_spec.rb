require "rails_helper"

# Epic #243, phase 1 — écran Comptabilité > Caisse > Motifs.
RSpec.describe "Comptabilité > Motifs de caisse", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { LegalEntity.create!(name: "Fondation test", form: "foundation", vat_regime: "exempt") }
  let(:account) { GeneralAccount.create!(code: "700300", name: "Bar et cellier", klass: 7, nature: "revenue") }

  before { sign_in user }

  def create_motif(label, position, **attrs)
    CashMotif.create!({ label: label, direction: "in", position: position,
                        general_account: account, legal_entity: entity }.merge(attrs))
  end

  def base_params(overrides = {})
    { cash_motif: { label: "Bar", direction: "in", general_account_id: account.id,
                    legal_entity_id: entity.id, position: 1, active: "1" }.merge(overrides) }
  end

  describe "GET /finance/cash/motifs" do
    it "liste les motifs avec leur sens et leur affectation" do
      create_motif("Bar", 1)
      create_motif("Dépôt en banque", 2, direction: "out", active: false)

      get finance_cash_motifs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bar", "Dépôt en banque")
      expect(response.body).to include("Entrée", "Sortie")
      expect(response.body).to include("700300")
      expect(response.body).to include("Actif", "Inactif")
      expect(response.body).to include("subnav-accounting")
    end

    it "renvoie vers le seed quand la liste est vide" do
      get finance_cash_motifs_path

      expect(response.body).to include("rake finance:seed_cash_motifs")
    end
  end

  describe "POST /finance/cash/motifs" do
    it "crée le motif" do
      expect { post finance_cash_motifs_path, params: base_params }.to change(CashMotif, :count).by(1)

      expect(response).to redirect_to(finance_cash_motifs_path)
      expect(CashMotif.last.general_account).to eq(account)
    end

    it "refuse un motif sans compte général" do
      expect { post finance_cash_motifs_path, params: base_params(general_account_id: "") }
        .not_to change(CashMotif, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /finance/cash/motifs/:id" do
    it "met à jour le sens" do
      motif = create_motif("Bar", 1)

      patch finance_cash_motif_path(motif), params: base_params(direction: "out")

      expect(response).to redirect_to(finance_cash_motifs_path)
      expect(motif.reload.direction).to eq("out")
    end
  end

  describe "POST /finance/cash/motifs/:id/move" do
    it "remonte un motif d'un cran" do
      premier  = create_motif("Bar", 1)
      deuxieme = create_motif("Épicerie", 2)

      post move_finance_cash_motif_path(deuxieme, direction: "up")

      expect(deuxieme.reload.position).to eq(1)
      expect(premier.reload.position).to eq(2)
    end

    it "descend un motif d'un cran" do
      premier  = create_motif("Bar", 1)
      deuxieme = create_motif("Épicerie", 2)

      post move_finance_cash_motif_path(premier, direction: "down")

      expect(premier.reload.position).to eq(2)
      expect(deuxieme.reload.position).to eq(1)
    end

    it "ne bouge rien quand le motif est déjà en tête" do
      premier = create_motif("Bar", 1)

      post move_finance_cash_motif_path(premier, direction: "up")

      expect(premier.reload.position).to eq(1)
    end
  end

  describe "désactivation / réactivation" do
    it "désactive sans détruire — une feuille passée garde son vocabulaire" do
      motif = create_motif("Bar", 1)

      patch deactivate_finance_cash_motif_path(motif)

      expect(motif.reload.active).to be(false)
      expect(CashMotif.count).to eq(1)
    end

    it "réactive" do
      motif = create_motif("Bar", 1, active: false)

      patch reactivate_finance_cash_motif_path(motif)

      expect(motif.reload.active).to be(true)
    end
  end

  it "n'expose aucune route de suppression" do
    expect { finance_cash_motif_path(1) }.not_to raise_error
    expect(Rails.application.routes.routes.map(&:name)).not_to include("destroy_finance_cash_motif")
  end

  it "exige une session" do
    sign_out user

    get finance_cash_motifs_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
