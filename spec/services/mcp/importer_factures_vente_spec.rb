require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Reprendre un lot OkiOki (Michael, 2026-10-30) : déjà au registre, ignorée ;
# écriture reprise trouvée, rattachée sans nouvelle écriture ; sinon passée au
# journal Ventes. Chaque facture séparément.
RSpec.describe Mcp::Server, "importer_factures_vente" do
  include FinanceBuilders

  let!(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:exercice) { build_fiscal_year(fondation, year: 2026) }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4, nature: "asset") }
  let!(:pains) { build_general_account(code: "700000", name: "Ventes de pains", klass: 7, nature: "revenue") }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:compte_bancaire) { build_cash_account(fondation, banque) }
  let!(:ekikrok) { ThirdParty.create!(name: "Ekikrok", kind: "customer") }
  let!(:ucoopia) { ThirdParty.create!(name: "Ucoopia", kind: "customer") }

  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: user) }

  def outil(arguments)
    server.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                    "params" => { "name" => "importer_factures_vente", "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(arguments)
    apercu = outil(arguments)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]))
    expect(resultat[:isError]).to be(false), texte(resultat)
    texte(resultat)
  end

  def vente(libelle, cents, tiers)
    Accounting::PostDocument.new(
      legal_entity: fondation, journal: "sales", entry_date: Date.new(2026, 10, 1), label: libelle,
      lines: [{ account: clients, debit_cents: cents, credit_cents: 0, third_party: tiers },
              { account: pains, debit_cents: 0, credit_cents: cents }]
    ).run!
  end

  def facture(numero, montant, client: "Ekikrok", **autres)
    { "numero" => numero, "date" => "2026-10-01", "client" => client, "montant" => montant,
      "lignes" => [{ "libelle" => "Pains", "montant_ht" => montant, "taux" => 0 }] }.merge(autres)
  end

  it "ignore les factures déjà au registre, rattache celles dont l'écriture existe et passe les autres" do
    ecriture = vente("2026-100 Ekikrok - pains", 30_559, ekikrok)
    virement = build_cash_entry(compte_bancaire, amount_cents: 12_250, entry_date: Date.new(2026, 10, 20))
    virement.update!(communication: "+++090/9337/55493+++")
    virement.cash_allocations.create!(general_account: clients, legal_entity: fondation, third_party: ucoopia, amount_cents: 12_250)
    Accounting::PostCashEntry.new(cash_entry: virement.reload).run!
    vente("2026-106 Ucoopia - pains", 12_250, ucoopia)
    SalesInvoices::Record.new(attributes: { legal_entity_id: fondation.id, third_party_id: ekikrok.id, number: "2026-090",
                                            issued_on: Date.new(2026, 9, 1), total_cents: 5_000,
                                            sales_invoice_lines_attributes: [{ general_account_id: pains.id, net_cents: 5_000 }] }).run!
    lot = { "compte_defaut" => "700000", "factures" => [
      facture("2026-090", "50"),
      facture("2026-100", "305,59"),
      facture("2026-106", "122,50", client: "Ucoopia", "communication" => "+++090/9337/55493+++"),
      facture("2026-120", "80", client: "Ucoopia")
    ] }

    apercu = texte(outil(lot))
    expect(apercu).to include("2 à rattacher", "1 à passer au journal Ventes", "1 déjà au registre", "2026-100", ecriture.reference)
    expect(SalesInvoice.count).to eq(1)

    sortie = nil
    expect { sortie = confirme(lot) }.to change(SalesInvoice, :count).by(3).and change(JournalEntry, :count).by(1)
    expect(sortie).to include("Fait : 4 facture(s)")

    expect(SalesInvoice.find_by!(number: "2026-100")).to have_attributes(journal_entry: ecriture, third_party: ekikrok)
    expect(SalesInvoice.find_by!(number: "2026-106")).to have_attributes(status: "paid", payment_reference: "+++090/9337/55493+++")
    expect(SalesInvoice.find_by!(number: "2026-120").journal_entry.journal).to eq("sales")

    expect(texte(outil(lot))).to include("4 déjà au registre")
  end

  it "refuse une facture dont le total contredit l'écriture, sans bloquer les autres" do
    vente("2026-100 Ekikrok - pains", 30_559, ekikrok)
    lot = { "compte_defaut" => "700000", "factures" => [facture("2026-100", "300"), facture("2026-121", "40")] }

    sortie = confirme(lot)

    expect(sortie).to include("1 refusées", "porte 305,59 €")
    expect(SalesInvoice.pluck(:number)).to eq(["2026-121"])
  end

  it "ne passe rien en rattacher_seulement, et dit pourquoi une facture est refusée" do
    lot = { "rattacher_seulement" => true, "factures" => [
      facture("2026-130", "10"),
      facture("2026-131", "10", client: "Inconnu SA")
    ] }

    expect { confirme(lot) }.not_to change(SalesInvoice, :count)
    expect(texte(outil(lot))).to include("2 sans écriture, laissées de côté")

    sans_compte = texte(outil({ "factures" => [facture("2026-132", "10", client: "Inconnu SA"), facture("2026-133", "10")] }))
    expect(sans_compte).to include("2 refusées", "Inconnu SA", "sans compte de produit")
  end

  it "relie une note de crédit à la facture du même lot" do
    lot = { "compte_defaut" => "700000", "factures" => [
      facture("2026-062", "20", "type" => "note_de_credit", "facture_corrigee" => "2026-061"),
      facture("2026-061", "100")
    ] }

    confirme(lot)

    expect(SalesInvoice.find_by!(number: "2026-062").credited_invoice.number).to eq("2026-061")
    expect(SalesInvoice.find_by!(number: "2026-061").remaining_cents).to eq(8_000)
  end
end
