require "rails_helper"
require Rails.root.join("spec/support/finance_builders")
require Rails.root.join("spec/support/mail_intake_helpers")

# Comptabilité > Fournisseurs & clients dans le connecteur (Michael,
# 2026-10-13) : la boite de réception de la compta, les tiers, les charges
# fixes et les factures de vente — aperçu d'abord, accord ensuite.
RSpec.describe Mcp::Server, "finances : fournisseurs et clients" do
  include FinanceBuilders
  include MailIntakeHelpers

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:telecom) { build_general_account(code: "614300", name: "Télécommunications", klass: 6, nature: "expense") }

  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456") }
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
    texte(resultat)
  end

  describe "la boite de réception" do
    let!(:proximus) { ThirdParty.create!(name: "Proximus", kind: "supplier") }
    let(:account) { MailAccount.create!(address: "compta@les4sources.be", purpose: "accounting") }
    let(:message) do
      imap = MailIntakeHelpers::FakeImap.new({ 1 => raw_mail(message_id: "x@proximus.be", pdf: text_pdf(["Facture 2026-77812", "Total 84,12"])) })
      MailIntake::Sync.new(mail_account: account, imap: imap).run!.first
    end
    let!(:piece) do
      message.mail_attachments.first.tap do |a|
        a.update!(proposal: {
                    "kind" => { "value" => "invoice" },
                    "third_party_id" => { "value" => proximus.id },
                    "legal_entity_id" => { "value" => entity.id },
                    "total_cents" => { "value" => 8_412 },
                    "number" => { "value" => "2026-77812" },
                    "issued_on" => { "value" => "2026-09-12" },
                    "due_on" => { "value" => "2026-10-15" }
                  })
      end
    end

    it "liste la pièce, l'encode depuis le mail avec son PDF, et classe le mail" do
      liste = texte(outil("boite_compta", {}))
      expect(liste).to include("a traiter 1", "Mail ##{message.id}", "Pièce ##{piece.id}", "fournisseur Proximus", "n° 2026-77812", "84,12 €")

      arguments = { "piece_mail" => piece.id, "lignes" => [{ "compte" => "614300", "montant" => "84,12" }] }
      apercu = texte(outil("enregistrer_facture_achat", arguments))
      expect(apercu).to include("Fournisseur Proximus", "n° 2026-77812", "total 84,12 €", "Pièce : « facture.pdf »")
      expect(PurchaseInvoice.count).to eq(0)

      expect(confirme("enregistrer_facture_achat", arguments)).to include("Mail classé")
      facture = PurchaseInvoice.last
      expect(facture).to have_attributes(third_party: proximus, number: "2026-77812", total_cents: 8_412,
                                         due_on: Date.new(2026, 10, 15), pdf_sha256: piece.sha256)
      expect(facture.document).to be_attached
      expect(piece.reload.purchase_invoice).to eq(facture)
      expect(message.reload.status).to eq("filed")

      deuxieme = outil("enregistrer_facture_achat", arguments)
      expect(texte(deuxieme)).to include("déjà encodée")
    end

    it "ignore un mail puis le remet dans la file" do
      confirme("geste_mail_compta", { "geste" => "ignorer", "mail" => message.id })
      expect(message.reload.status).to eq("ignored")
      expect(message.handled_by).to eq(user)
      expect(texte(outil("boite_compta", { "statut" => "ignores" }))).to include("Mail ##{message.id}")

      confirme("geste_mail_compta", { "geste" => "remettre", "mail" => message.id })
      expect(message.reload.status).to eq("pending")
    end
  end

  describe "les tiers" do
    it "crée un fournisseur, refuse un doublon de TVA, puis le désactive" do
      confirme("enregistrer_tiers", { "nom" => "Voo", "tva" => "BE0123456749", "email" => "factures@voo.be" })
      voo = ThirdParty.find_by(name: "Voo")
      expect(voo).to have_attributes(kind: "supplier", code: "VOO", vat_number: "BE0123456749")

      doublon = outil("enregistrer_tiers", { "nom" => "VOO SA", "tva" => "BE 0123.456.749" })
      expect(texte(doublon)).to include("porte déjà ce numéro de TVA")

      confirme("enregistrer_tiers", { "tiers" => "Voo", "actif" => false })
      expect(voo.reload.active).to be(false)
      expect(texte(outil("tiers", {}))).not_to include("Voo")
      expect(texte(outil("tiers", { "inactifs" => true }))).to include("##{voo.id} Voo", "DÉSACTIVÉ")
    end
  end

  describe "les charges fixes" do
    let!(:voo) { ThirdParty.create!(name: "Voo", kind: "supplier") }

    it "crée une charge mensuelle, la corrige puis la supprime" do
      arguments = { "libelle" => "Internet Voo", "montant" => "67,76", "premiere_echeance" => Date.current.next_month.beginning_of_month.iso8601,
                    "fournisseur" => "Voo", "compte" => "614300" }
      confirme("charge_fixe", arguments)
      charge = RecurringExpense.last
      expect(charge).to have_attributes(amount_cents: 6_776, frequency: "monthly", legal_entity: entity, third_party: voo)
      expect(texte(outil("charges_fixes", {}))).to include("Internet Voo", "67,76 € chaque mois", "813,12 € par an")

      confirme("charge_fixe", { "charge" => "voo", "frequence" => "trimestrielle" })
      expect(charge.reload.frequency).to eq("quarterly")

      confirme("charge_fixe", { "charge" => charge.id, "supprimer" => true })
      expect(RecurringExpense.count).to eq(0)
    end
  end

  describe "les factures de vente" do
    let!(:customer) { Customer.create!(first_name: "Camille", last_name: "Renard", email: "camille@example.org") }
    let!(:stay) do
      Stay.create!(customer: customer, arrival_date: Date.new(2026, 6, 1), departure_date: Date.new(2026, 6, 4),
                   total_amount_cents: 130_000, invoice_status: "requested")
    end

    it "montre la file, enregistre la facture du séjour, la corrige puis la retire" do
      expect(texte(outil("factures_vente", { "a_facturer" => true }))).to include("sejour ##{stay.id}", "1300,00 €")

      confirme("facture_vente", { "geste" => "enregistrer", "reservation" => stay.id, "numero" => "2026-001" })
      facture = SalesInvoice.last
      expect(facture).to have_attributes(number: "2026-001", total_cents: 130_000, status: "issued", legal_entity: entity)
      expect(stay.reload.invoice_status).to eq("sent")
      expect(texte(outil("factures_vente", {}))).to include("n° 2026-001", "émise", "sejour ##{stay.id}")

      doublon = outil("facture_vente", { "geste" => "enregistrer", "reservation" => stay.id, "numero" => "2026-002" })
      expect(texte(doublon)).to include("déjà rattaché")

      confirme("facture_vente", { "geste" => "corriger", "facture" => "2026-001", "montant" => "1250" })
      expect(facture.reload.total_cents).to eq(125_000)

      confirme("facture_vente", { "geste" => "retirer", "facture" => "##{facture.id}" })
      expect(SalesInvoice.count).to eq(0)
    end
  end
end
