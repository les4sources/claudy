require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Reprise des journaux d'achats et de ventes Winbooks (Michael, 2026-10-13) :
# les paiements sont déjà au grand livre, il manque les factures en face.
RSpec.describe Mcp::Server, "reprise de pièces Winbooks" do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2022) }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4, nature: "asset") }
  let!(:gaz) { build_general_account(code: "612003", name: "Gaz", klass: 6, nature: "expense").tap { |c| c.update!(active: false) } }
  let!(:salle) { build_general_account(code: "700001", name: "Location salle", klass: 7, nature: "revenue") }
  let!(:antargaz) { ThirdParty.create!(code: "ANTARGAZ", name: "Antargaz", kind: "supplier") }
  let!(:client) { ThirdParty.create!(code: "COMMUNEYV", name: "Commune d'Yvoir", kind: "customer") }

  let!(:chloe) { Human.create!(name: "Chloé", email: "chloe@example.com") }
  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456", human: chloe) }
  let(:server) { described_class.new(user: user) }

  before { Accounting::ImportLedgerDocument.reset_cache! }

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

  def achat(ref = "2022:ACHATS:2", montant = "121.00")
    { "ref" => ref, "journal" => "achats", "date" => "2022-01-14", "libelle" => "Antargaz — location citerne gaz",
      "lignes" => [{ "compte" => "440000", "tiers" => "ANTARGAZ", "credit" => montant, "libelle" => "location citerne gaz" },
                   { "compte" => "612003", "debit" => montant, "libelle" => "Gaz" }] }
  end

  def vente
    { "ref" => "2022:VENTES:1", "journal" => "ventes", "date" => "2022-03-02", "libelle" => "Commune d'Yvoir — salle",
      "lignes" => [{ "compte" => "400000", "tiers" => "COMMUNEYV", "debit" => "250" },
                   { "compte" => "700001", "credit" => "250" }] }
  end

  def arguments(*pieces) = { "pieces" => pieces, "motif" => "reprise Winbooks achats 2022" }

  it "reprend une facture d'achat et une de vente, sur un compte archivé, sans toucher la trésorerie" do
    apercu = texte(outil("reprendre_pieces", arguments(achat, vente)))
    expect(apercu).to include("2 à reprendre", "Journal Achats : 1 pièce(s), 121,00 €", "1 compte(s) archivé(s)")
    expect(JournalEntry.count).to eq(0)

    expect(confirme("reprendre_pieces", arguments(achat, vente))).to include("2 pièce(s) reprise(s)")

    facture = LedgerDocument.find_by!(source_system: "winbooks", external_ref: "winbooks:2022:ACHATS:2").journal_entries.sole
    expect(facture.journal).to eq("purchases")
    expect(facture.whodunnit).to eq("claude:chloe@example.com — reprise Winbooks achats 2022")
    fournisseur = facture.journal_lines.find_by!(general_account: fournisseurs)
    expect([fournisseur.credit_cents, fournisseur.third_party]).to eq([12_100, antargaz])
    expect(facture.journal_lines.find_by!(general_account: gaz).debit_cents).to eq(12_100)
    expect(JournalEntry.find_by!(journal: "sales").journal_lines.find_by!(general_account: clients).third_party).to eq(client)
  end

  it "ignore une pièce déjà reprise au lot suivant" do
    confirme("reprendre_pieces", arguments(achat))

    expect(texte(outil("reprendre_pieces", arguments(achat, vente)))).to include("1 à reprendre, 1 déjà reprise(s)")
    confirme("reprendre_pieces", arguments(achat, vente))
    expect(JournalEntry.count).to eq(2)
  end

  it "trouve un tiers créé pour l'occasion par son nom, quand son code diffère de celui de Winbooks" do
    croix_rouge = ThirdParty.create!(name: "Croix Rouge de Belgique", kind: "customer")
    piece = vente.deep_dup.tap { |p| p["lignes"][0]["tiers"] = "croix rouge de belgique" }

    confirme("reprendre_pieces", arguments(piece))

    expect(JournalLine.find_by!(general_account: clients).third_party).to eq(croix_rouge)
  end

  it "refuse tout le lot et liste chaque problème avant d'écrire" do
    inconnue = achat("2022:ACHATS:3").deep_dup.tap { |p| p["lignes"][0]["tiers"] = "INCONNU" }
    bancale = achat("2022:ACHATS:4").deep_dup.tap { |p| p["lignes"][1]["debit"] = "120" }
    hors = achat("2022:ACHATS:5").merge("date" => "2023-01-03")
    tresorerie = achat("2022:ACHATS:6").deep_dup.tap { |p| p["lignes"][1]["compte"] = "550000" }

    resultat = outil("reprendre_pieces", arguments(achat, inconnue, bancale, hors, tresorerie))

    expect(resultat[:isError]).to be(true)
    expect(texte(resultat)).to include("tiers INCONNU inconnu", "2022:ACHATS:4 : déséquilibrée",
                                       "aucun exercice ne couvre le 2023-01-03", "compte de trésorerie 550000")
    expect(LedgerDocument.count).to eq(0)
  end
end
