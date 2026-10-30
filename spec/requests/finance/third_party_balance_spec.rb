require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Comptabilité › États › Balance tiers (2026-10-30), et le grand livre filtré
# sur un tiers où elle mène.
RSpec.describe "Finances > Balance tiers", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:bank) { build_general_account(code: "550000", name: "Banque") }
  let!(:suppliers) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:customers) { build_general_account(code: "400000", name: "Clients", klass: 4, nature: "asset") }
  let!(:expense) { build_general_account(code: "610000", name: "Loyers", klass: 6, nature: "expense") }
  let(:proximus) { ThirdParty.create!(name: "Proximus", kind: "supplier") }
  let(:vivaqua) { ThirdParty.create!(name: "Vivaqua", kind: "supplier") }

  before do
    sign_in user
    [[proximus, 30_000], [vivaqua, 12_000]].each do |third_party, cents|
      Accounting::PostDocument.new(
        legal_entity: entity, journal: "purchases", entry_date: Date.current.beginning_of_year, label: "Facture",
        lines: [{ account: expense, debit_cents: cents },
                { account: suppliers, credit_cents: cents, third_party: third_party, label: "Facture #{third_party.name}" }]
      ).run!
    end
  end

  it "liste ce qu'on doit à chaque fournisseur" do
    get finance_third_party_balance_path

    expect(response).to have_http_status(:ok)
    corps = CGI.unescapeHTML(response.body)
    expect(corps).to include("Balance tiers", "Nous devons", "Proximus", "Vivaqua")
    expect(corps).to match(/Nous devons.{0,200}420/m)
    expect(corps.index("Proximus")).to be < corps.index("Vivaqua")
  end

  it "filtre par structure et garde le côté choisi" do
    autre = build_legal_entity(name: "Domaine d'Ahinvaux SRL", form: "srl")
    build_fiscal_year(autre, year: Date.current.year)

    get finance_third_party_balance_path(side: "customers", legal_entity_id: autre.id)

    corps = CGI.unescapeHTML(response.body)
    expect(corps).to include("Aucun client avec un solde").and include("side=customers")
    expect(corps).not_to include("Proximus")
  end

  it "mène au grand livre du compte, filtré sur le tiers" do
    get finance_ledger_path(general_account_id: suppliers.id, third_party_id: proximus.id,
                            from: Date.current.beginning_of_year, to: Date.current.end_of_year)

    corps = CGI.unescapeHTML(response.body)
    expect(corps).to include("Facture Proximus").and match(/Clôture.{0,200}300/m)
    expect(corps).not_to include("Facture Vivaqua")
  end
end
