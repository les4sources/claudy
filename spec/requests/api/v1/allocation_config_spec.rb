require "rails_helper"

# La configuration du rapprochement assisté par l'API.
#
# Ce qui est testé ici, c'est la frontière : un agent peut poser ses règles et
# ses motifs, il ne peut PAS comptabiliser. Et les deux invariants qui rendent
# cette écriture sans danger — une règle sans critère est refusée (elle
# s'appliquerait à tout), et réaffecter un motif ne réécrit aucune ligne déjà
# saisie, parce que l'allocation en est une copie et non une référence.
RSpec.describe "API v1 — configuration du rapprochement", type: :request do
  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  before { ENV["AGENT_API_TOKEN"] = token }
  after { ENV.delete("AGENT_API_TOKEN") }

  def body = JSON.parse(response.body)

  let!(:entity) { LegalEntity.create!(name: "Fondation Les 4 Sources", form: "foundation", vat_regime: "exempt") }
  let!(:bar) { GeneralAccount.create!(code: "701001", name: "Bar", klass: 7, nature: "revenue") }
  let!(:cellier) { GeneralAccount.create!(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }
  let!(:accueil) { Team.create!(name: "Pôle Accueil") }

  describe "POST /api/v1/allocation_rules" do
    let(:regle) do
      { allocation_rule: { label: "Bar — virements", communication_contains: "bar ",
                           direction: "incoming", confidence: 90,
                           general_account_code: "701001", team_name: "Pôle Accueil",
                           legal_entity_name: "Fondation Les 4 Sources" } }
    end

    it "crée une règle et résout le compte par son code, le pôle par son nom" do
      post "/api/v1/allocation_rules", params: regle.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "general_account_code")).to eq("701001")
      expect(body.dig("data", "team_name")).to eq("Pôle Accueil")
      expect(body.dig("data", "criteria", "communication_contains")).to eq("bar ")
    end

    # L'espace final n'est pas un détail : sans lui, « bar » reconnaît
    # « Cabaronde ». L'API doit rendre le critère au caractère près.
    it "conserve un critère à l'espace près" do
      post "/api/v1/allocation_rules", params: regle.to_json, headers: headers

      expect(AllocationRule.find_by(label: "Bar — virements").communication_contains).to eq("bar ")
    end

    it "retrouve la règle existante sur son libellé au lieu d'en créer une seconde" do
      post "/api/v1/allocation_rules", params: regle.to_json, headers: headers

      expect {
        post "/api/v1/allocation_rules", params: regle.to_json, headers: headers
      }.not_to change(AllocationRule, :count)

      expect(response).to have_http_status(:ok)
    end

    it "refuse une règle sans aucun critère" do
      post "/api/v1/allocation_rules",
           params: { allocation_rule: { label: "Fourre-tout", general_account_code: "701001",
                                        legal_entity_name: "Fondation Les 4 Sources" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["messages"].join).to include("sans aucun critère")
    end

    it "refuse un compte général inconnu plutôt que de poser une règle muette" do
      post "/api/v1/allocation_rules",
           params: { allocation_rule: { label: "Bar", communication_contains: "bar ",
                                        general_account_code: "999999",
                                        legal_entity_name: "Fondation Les 4 Sources" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["message"]).to eq("Compte général inconnu : 999999.")
      expect(AllocationRule.count).to eq(0)
    end

    it "exige un jeton" do
      post "/api/v1/allocation_rules", params: regle.to_json,
                                       headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/allocation_rules" do
    it "rend les règles dans leur ordre d'application" do
      AllocationRule.create!(label: "Pain", communication_contains: "pain", position: 8,
                             general_account: cellier, legal_entity: entity)
      AllocationRule.create!(label: "Massepain — garde", communication_contains: "massepain",
                             position: 3, general_account: cellier, legal_entity: entity)

      get "/api/v1/allocation_rules", headers: headers

      expect(body["data"].map { |r| r["label"] }).to eq(["Massepain — garde", "Pain"])
    end
  end

  describe "DELETE /api/v1/allocation_rules/:id" do
    it "supprime la règle" do
      regle = AllocationRule.create!(label: "Bar", communication_contains: "bar ",
                                     general_account: bar, legal_entity: entity)

      delete "/api/v1/allocation_rules/#{regle.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(AllocationRule.find_by(id: regle.id)).to be_nil
    end
  end

  describe "POST /api/v1/cash_motifs" do
    let(:motif) do
      { cash_motif: { label: "Bar", direction: "in", general_account_code: "701001",
                      team_name: "Pôle Accueil", legal_entity_name: "Fondation Les 4 Sources" } }
    end

    it "crée un motif et l'adresse ensuite par son libellé" do
      post "/api/v1/cash_motifs", params: motif.to_json, headers: headers
      expect(response).to have_http_status(:created)

      get "/api/v1/cash_motifs/Bar", headers: headers
      expect(body.dig("data", "general_account_code")).to eq("701001")
    end

    it "retrouve le motif existant sur son libellé" do
      post "/api/v1/cash_motifs", params: motif.to_json, headers: headers

      expect {
        post "/api/v1/cash_motifs", params: motif.to_json, headers: headers
      }.not_to change(CashMotif, :count)

      expect(response).to have_http_status(:ok)
    end

    it "refuse un motif sans compte général — ce serait un motif qui n'affecte rien" do
      post "/api/v1/cash_motifs",
           params: { cash_motif: { label: "Divers", direction: "in",
                                   legal_entity_name: "Fondation Les 4 Sources" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/cash_motifs/:id" do
    # L'invariant qui rend l'écriture par API sans danger sur un exercice en
    # cours : l'allocation d'une ligne est une COPIE du motif, pas une
    # référence. Réaffecter le motif ne doit rien réécrire.
    it "ne réécrit pas l'affectation d'une ligne déjà saisie" do
      FiscalYear.create!(legal_entity: entity, starts_on: Date.current.beginning_of_year,
                         ends_on: Date.current.end_of_year, status: "open")
      caisse_compte = GeneralAccount.create!(code: "570000", name: "Caisse", klass: 5, nature: "asset")
      caisse = CashAccount.create!(name: "Caisse du bar", kind: "cash", legal_entity: entity,
                                   general_account: caisse_compte)
      motif = CashMotif.create!(label: "Bar", direction: "in", general_account: bar, legal_entity: entity)
      entree = Finance::RecordCashLine.new(cash_account: caisse, motif: motif, entry_date: Date.current,
                                           label: "Deux bières", amount_cents: 700).run!

      patch "/api/v1/cash_motifs/#{motif.id}",
            params: { cash_motif: { general_account_code: "701002" } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(body.dig("data", "general_account_code")).to eq("701002")
      expect(entree.cash_allocations.first.general_account_id).to eq(bar.id)
    end
  end

  describe "la frontière de l'API" do
    # Poser une règle ne comptabilise pas : l'acceptation reste au navigateur,
    # devant quelqu'un qui voit combien de lignes il touche.
    it "n'expose aucune route d'acceptation des suggestions" do
      expect {
        post "/api/v1/allocation_suggestions/1", headers: headers
      }.to raise_error(ActionController::RoutingError)
    end
  end
end
