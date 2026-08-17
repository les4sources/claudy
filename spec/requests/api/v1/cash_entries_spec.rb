require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #200 — écrire une ligne de trésorerie que la banque ne raconte pas.
# La caisse en espèces du domaine tient cinquante mois de mouvements depuis
# janvier 2022, et aucun fichier CODA ne les porte.
RSpec.describe "API v1 — lignes de trésorerie", type: :request do
  include FinanceBuilders

  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  before { ENV["AGENT_API_TOKEN"] = token }
  after { ENV.delete("AGENT_API_TOKEN") }

  def body = JSON.parse(response.body)

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:compte) do
    CashAccount.create!(name: "Caisse du bar", kind: "cash", legal_entity: entity,
                        general_account: build_general_account(code: "570000", name: "Caisse"))
  end

  def poste(attrs)
    post "/api/v1/cash_entries", params: { cash_entry: attrs }.to_json, headers: headers
  end

  it "crée une ligne et renvoie le solde du compte de trésorerie" do
    poste(cash_account_id: compte.id, entry_date: "2022-01-01", amount_cents: 7000,
          label: "Nuit Pierre et Delphine", external_ref: "caisse:2022-01:L4")

    expect(response).to have_http_status(:created)
    expect(body.dig("data", "amount", "cents")).to eq(7000)
    expect(body.dig("data", "status")).to eq("pending")
    expect(body.dig("meta", "cash_account_balance_cents")).to eq(7000)
  end

  # Une reprise connaît « Caisse du bar », pas un identifiant technique.
  it "résout le compte par son nom" do
    poste(cash_account_name: "Caisse du bar", entry_date: "2022-01-06", amount_cents: -13_780,
          label: "Vidange Botton", external_ref: "caisse:2022-01:L9")

    expect(response).to have_http_status(:created)
    expect(CashEntry.last.cash_account).to eq(compte)
  end

  it "refuse un compte de trésorerie inconnu au lieu d'en créer un" do
    expect {
      poste(cash_account_name: "Caisse fantôme", entry_date: "2022-01-06",
            amount_cents: 100, label: "Test")
    }.not_to change(CashEntry, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "met à jour au lieu de dupliquer quand la référence revient" do
    attrs = { cash_account_id: compte.id, entry_date: "2022-01-01", amount_cents: 7000,
              label: "Nuit Pierre et Delphine", external_ref: "caisse:2022-01:L4" }
    poste(attrs)

    expect { poste(attrs.merge(amount_cents: 8000)) }.not_to change(CashEntry, :count)

    expect(response).to have_http_status(:ok)
    expect(CashEntry.sole.amount_cents).to eq(8000)
  end

  # Sans référence, rien ne rattache la seconde requête à la première : on crée.
  # C'est voulu, et c'est pour ça que la reprise en fournit toujours une.
  it "crée deux lignes quand aucune référence n'est fournie" do
    attrs = { cash_account_id: compte.id, entry_date: "2022-01-23", amount_cents: 3000, label: "Bar" }

    expect { 2.times { poste(attrs) } }.to change(CashEntry, :count).by(2)
  end

  it "sort en 409 sur une ligne déjà comptabilisée" do
    # La date tombe dans l'exercice ouvert du builder : ce qui compte ici est
    # l'état « comptabilisée », pas le chemin qui y mène.
    jour = fiscal_year.starts_on + 1
    entry = CashEntry.create!(cash_account: compte, entry_date: jour, amount_cents: 7000,
                              label: "Nuit", external_ref: "caisse:2022-01:L4")
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "cash", entry_date: jour, label: "Test", source: entry,
      lines: [{ account: GeneralAccount.find_by(code: "570000"), debit_cents: 7000 },
              { account: build_general_account(code: "700000", name: "Produits"), credit_cents: 7000 }]
    ).run!
    expect(entry.reload).to be_posted

    poste(cash_account_id: compte.id, entry_date: jour.to_s, amount_cents: 9999,
          label: "Correction", external_ref: "caisse:2022-01:L4")

    expect(response).to have_http_status(:conflict)
    expect(entry.reload.amount_cents).to eq(7000)
  end

  it "refuse un montant nul avec un 422 lisible" do
    poste(cash_account_id: compte.id, entry_date: "2022-01-01", amount_cents: 0, label: "Rien")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(body["messages"].join).to match(/montant|amount/i)
  end

  it "refuse sans jeton" do
    post "/api/v1/cash_entries",
         params: { cash_entry: { cash_account_id: compte.id, entry_date: "2022-01-01",
                                 amount_cents: 100, label: "Test" } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "filtre par compte et par période, dans l'ordre chronologique" do
    CashEntry.create!(cash_account: compte, entry_date: Date.new(2022, 3, 1), amount_cents: 100, label: "Mars")
    CashEntry.create!(cash_account: compte, entry_date: Date.new(2022, 1, 1), amount_cents: 200, label: "Janvier")

    get "/api/v1/cash_entries", params: { cash_account_id: compte.id, from: "2022-02-01" }, headers: headers

    expect(body["data"].map { |e| e["label"] }).to eq(["Mars"])
  end
end
