require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La page Import CODA prévenait qu'un compte n'avait pas d'IBAN sans qu'aucun
# écran ne permît de le poser (Michael, 2026-10-19).
RSpec.describe "Comptabilité > Comptes de trésorerie", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let(:bank_ledger) { build_general_account(code: "550002", name: "Épargne") }
  let!(:epargne) { build_cash_account(entity, bank_ledger, name: "Fondation — Compte épargne") }

  before { sign_in user }

  it "liste les comptes et signale celui qui n'a pas d'IBAN" do
    caisse = build_cash_account(entity, build_general_account(code: "570000", name: "Caisse"), name: "Caisse", kind: "cash")

    get finance_cash_accounts_path

    expect(response).to have_http_status(:ok)
    expect(CGI.unescapeHTML(response.body)).to include("Fondation — Compte épargne", "Pas d'IBAN")
    expect(response.body).to include(edit_finance_cash_account_path(epargne))
    expect(response.body).not_to include(edit_finance_cash_account_path(caisse))
  end

  it "enregistre l'IBAN, rangé par groupes de quatre" do
    patch finance_cash_account_path(epargne), params: { cash_account: { iban: "be57523044800335" } }

    expect(response).to redirect_to(finance_cash_accounts_path)
    expect(epargne.reload.iban).to eq("BE57 5230 4480 0335")
  end

  it "refuse un IBAN mal recopié" do
    patch finance_cash_account_path(epargne), params: { cash_account: { iban: "BE57 5230 4480 0336" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(CGI.unescapeHTML(response.body)).to include("n'est pas un IBAN valide")
    expect(epargne.reload.iban).to be_nil
  end

  it "refuse un IBAN déjà porté par un autre compte" do
    courant = build_cash_account(entity, build_general_account(code: "550000", name: "Triodos"), name: "Triodos courant")
    courant.update!(iban: "BE57 5230 4480 0335")

    patch finance_cash_account_path(epargne), params: { cash_account: { iban: "BE57523044800335" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(CGI.unescapeHTML(response.body)).to include("déjà porté par « Triodos courant »")
  end

  it "efface l'IBAN laissé vide" do
    epargne.update!(iban: "BE57 5230 4480 0335")

    patch finance_cash_account_path(epargne), params: { cash_account: { iban: "" } }

    expect(epargne.reload.iban).to be_nil
  end

  it "ne touche pas l'IBAN d'une caisse" do
    caisse = build_cash_account(entity, build_general_account(code: "570000", name: "Caisse"), name: "Caisse", kind: "cash")

    expect {
      patch finance_cash_account_path(caisse), params: { cash_account: { iban: "BE57523044800335" } }
    }.to raise_error(ActiveRecord::RecordNotFound)
    expect(caisse.reload.iban).to be_nil
  end

  describe "l'avertissement de la page Import CODA" do
    it "nomme le compte en banque sans IBAN et mène à sa saisie" do
      get finance_coda_imports_path

      expect(CGI.unescapeHTML(response.body)).to include("n'ont pas d'IBAN", "Fondation — Compte épargne")
      expect(response.body).to include(edit_finance_cash_account_path(epargne))
    end

    # Une caisse ou un compte Stripe n'a pas d'IBAN, et c'est normal.
    it "ne compte pas la caisse" do
      epargne.update!(iban: "BE57 5230 4480 0335")
      build_cash_account(entity, build_general_account(code: "570000", name: "Caisse"), name: "Caisse", kind: "cash")

      get finance_coda_imports_path

      expect(CGI.unescapeHTML(response.body)).not_to include("n'ont pas d'IBAN")
    end
  end
end
