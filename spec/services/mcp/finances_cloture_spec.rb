require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Clôture, comptes annuels et immobilisations dans le connecteur (revue
# expert-comptable du 2026-10-20).
RSpec.describe Mcp::Server, "finances : clôture et états annuels" do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:year_2025) { build_fiscal_year(entity, year: 2025) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
  let!(:ventes) { build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue") }
  let!(:mobilier) { build_general_account(code: "240000", name: "Mobilier", klass: 2) }
  let!(:amortissements) { build_general_account(code: "240001", name: "Amortissements mobilier", klass: 2) }
  let!(:dotations) { build_general_account(code: "630100", name: "Dotations aux amortissements", klass: 6, nature: "expense") }

  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: user) }

  before do
    post_simple_entry(entity: entity, debit_account: banque, credit_account: ventes, amount_cents: 300_000,
                      entry_date: Date.new(2025, 5, 1))
  end

  def outil(name, arguments)
    server.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                    "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(name, arguments)
    apercu = outil(name, arguments)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(name, arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]))
    expect(resultat[:isError]).to be(false), texte(resultat)
    texte(resultat)
  end

  it "lit les comptes annuels au schéma BNB" do
    sortie = texte(outil("comptes_annuels", { "annee" => 2025, "detail" => true }))

    expect(sortie).to include("Comptes annuels 2025", "BILAN — ACTIF", "COMPTE DE RÉSULTATS", "550000 Banque")
  end

  it "inscrit un bien, passe sa dotation puis l'annule" do
    confirme("immobilisation", { "nom" => "Poêle", "acquis_le" => "2025-09-15", "valeur" => "1200", "duree" => 5,
                                 "compte" => "240000", "compte_amortissements" => "240001" })
    bien = FixedAsset.last
    expect(bien).to have_attributes(acquisition_cents: 120_000, expense_account: dotations, legal_entity: entity)
    expect(texte(outil("immobilisations", { "annee" => 2025 }))).to include("Poêle", "dotation 2025 à passer")

    confirme("amortissements", { "geste" => "passer", "annee" => 2025 })
    dotation = bien.reload.depreciations.first
    expect(dotation.amount_cents).to eq(8_000)

    confirme("amortissements", { "geste" => "annuler", "dotation" => dotation.id })
    expect(bien.reload.depreciations).to be_empty
  end

  it "clôture en posant l'à-nouveau, puis rouvre avec un motif" do
    cloture = { "exercice" => "2025", "entite" => "Fondation Les 4 Sources", "cloturer" => true, "a_nouveau" => "poser" }
    expect(texte(outil("exercice", cloture))).to include("IRRÉVERSIBLE", "693000")
    confirme("exercice", cloture)

    expect(year_2025.reload).to be_closed
    year_2026 = entity.fiscal_years.reload.find { |year| year.starts_on.year == 2026 }
    expect(Accounting::Balances.opening?(year_2026)).to be(true)

    expect(outil("exercice", { "exercice" => "2025", "entite" => "Fondation Les 4 Sources", "rouvrir" => true })[:isError]).to be(true)
    confirme("exercice", { "exercice" => "2025", "entite" => "Fondation Les 4 Sources", "rouvrir" => true, "motif" => "Facture oubliée" })
    expect(year_2025.reload).not_to be_closed
  end
end
