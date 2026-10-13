require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Reprise Winbooks (Michael, 2026-10-13) : une ligne oubliée reçoit le compte
# archivé que portent ses voisines déjà reprises, par son code exact.
RSpec.describe Mcp::Server, "affectation sur un compte Winbooks archivé" do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2022) }
  let!(:caisse_generale) { build_general_account(code: "570000", name: "Caisse") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:lamas) do
    build_general_account(code: "601601", name: "Animaux - Lamas", klass: 6, nature: "expense").tap { |c| c.update!(active: false) }
  end
  let!(:caisse) { build_cash_account(entity, caisse_generale, name: "Caisse du domaine", kind: "cash") }
  let!(:botton) { ThirdParty.create!(code: "BOTTON", name: "Botton", kind: "supplier") }

  let!(:chloe) { Human.create!(name: "Chloé", email: "chloe@example.com") }
  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456", human: chloe) }
  let(:server) { described_class.new(user: user) }

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
    resultat
  end

  def ligne(cents, label)
    build_cash_entry(caisse, amount_cents: cents, entry_date: Date.new(2022, 1, 7), label: label)
  end

  it "accepte un compte archivé sur son code exact, et le dit" do
    entry = ligne(-7_000, "Parage Lamas")
    arguments = { "ligne" => entry.id, "parts" => [{ "compte" => "601601", "libelle" => "Animaux - Lamas — parage lamas" }],
                  "motif" => "reprise Winbooks caisse 2022" }

    expect(texte(outil("affecter_ligne", arguments))).to include("601601", "(compte archivé)")
    confirme("affecter_ligne", arguments)

    expect(entry.reload).to be_posted
    expect(entry.cash_allocations.sole.general_account).to eq(lamas)
  end

  it "ne trouve pas un compte archivé par son nom" do
    entry = ligne(-7_000, "Parage Lamas")
    resultat = outil("affecter_ligne", { "ligne" => entry.id, "parts" => [{ "compte" => "lamas" }] })

    expect(resultat[:isError]).to be(true)
    expect(texte(resultat)).to include("Aucun compte actif")
  end

  it "rattache un paiement fournisseur à son tiers" do
    entry = ligne(-13_780, "vidange Botton")
    confirme("affecter_ligne", { "ligne" => entry.id, "parts" => [{ "compte" => "440000", "tiers" => "Botton" }] })

    expect(entry.reload.cash_allocations.sole).to have_attributes(general_account_id: fournisseurs.id, third_party_id: botton.id)
  end
end
