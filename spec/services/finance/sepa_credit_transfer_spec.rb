require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le fichier de virements SEPA pour l'import de Triodos (Michael, 2026-11-05).
# Le fichier produit est validé contre le schéma XSD officiel pain.001.001.03 :
# un fichier que la banque refuse, c'est un mercredi matin perdu.
RSpec.describe Finance::SepaCreditTransfer do
  include FinanceBuilders

  let(:schema) { Nokogiri::XML::Schema(File.read(Rails.root.join("spec/fixtures/sepa/pain.001.001.03.xsd"))) }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Triodos") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte) { build_cash_account(entity, banque).tap { |a| a.update!(iban: "BE91 5230 0000 0176") } }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz Belgium", kind: "supplier", iban: "BE68539007547034") }

  def facture(tiers: antargaz, total: 12_000, number: "F-1", reference: nil)
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: tiers, number: number, payment_reference: reference,
                               issued_on: Date.new(2026, 6, 1), total_cents: total)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
    PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
  end

  def fichier(payables, **options)
    described_class.new(legal_entity: entity, debtor_account: compte, payables: payables, **options)
  end

  def xml(file) = Nokogiri::XML(file.to_xml).tap(&:remove_namespaces!)

  it "écrit un pain.001.001.03 valide, un virement par dette, sans paiement groupé" do
    a = facture(number: "F-1", total: 12_000)
    b = facture(number: "F-2", total: 4_550, tiers: ThirdParty.create!(name: "Élec Énergie SA", kind: "supplier", iban: "DE89370400440532013000"))

    file = fichier([a, b], execution_date: Date.current + 2)
    doc = Nokogiri::XML(file.to_xml)

    expect(schema.validate(doc)).to be_empty
    doc.remove_namespaces!
    expect(doc.at("GrpHdr/NbOfTxs").text).to eq("2")
    expect(doc.at("GrpHdr/CtrlSum").text).to eq("165.50")
    expect(doc.at("PmtInf/BtchBookg").text).to eq("false")
    expect(doc.at("PmtInf/ReqdExctnDt").text).to eq((Date.current + 2).iso8601)
    expect(doc.at("DbtrAcct/Id/IBAN").text).to eq("BE91523000000176")
    expect(doc.at("DbtrAgt/FinInstnId/BIC").text).to eq("TRIOBEBB")
    expect(doc.xpath("//CdtTrfTxInf/Cdtr/Nm").map(&:text)).to eq(["Antargaz Belgium", "Elec Energie SA"])
    expect(doc.xpath("//CdtTrfTxInf/RmtInf/Ustrd").map(&:text)).to eq(%w[F-1 F-2])
    expect(doc.xpath("//EndToEndId").map(&:text)).to eq(["PI-#{a.id}", "PI-#{b.id}"])
    expect(file.filename).to eq("virements-fondation-les-4-sources-#{(Date.current + 2).iso8601}.xml")
  end

  it "envoie la communication structurée belge comme référence structurée, pas en texte" do
    a = facture(reference: "+++000/0024/11862+++")

    doc = xml(fichier([a]))

    expect(doc.at("RmtInf/Strd/CdtrRefInf/Ref").text).to eq("000002411862")
    expect(doc.at("RmtInf/Strd/CdtrRefInf/Tp/Issr").text).to eq("BBA")
    expect(doc.at("RmtInf/Ustrd")).to be_nil
  end

  it "ne vire que le reste d'une dette déjà en partie rapprochée" do
    a = facture(total: 10_000)
    sortie = build_cash_entry(compte, amount_cents: -3_000)
    sortie.cash_allocations.create!(general_account: fournisseurs, amount_cents: -3_000, legal_entity: entity,
                                    document: a, third_party: antargaz)

    doc = xml(fichier([a.reload]))

    expect(doc.at("InstdAmt").text).to eq("70.00")
    expect(doc.at("InstdAmt")["Ccy"]).to eq("EUR")
  end

  it "ne paie rien : la facture reste à payer après la génération" do
    a = facture

    fichier([a]).to_xml

    expect(a.reload.status).to eq("to_pay")
    expect(Finance::PayableQueue.new(legal_entity: entity).rows).to include(a)
  end

  it "donne NOTPROVIDED quand la banque débitrice n'est pas connue" do
    compte.update!(iban: "DE89370400440532013000")
    doc = Nokogiri::XML(fichier([facture]).to_xml)

    expect(schema.validate(doc)).to be_empty
    expect(doc.remove_namespaces!.at("DbtrAgt/FinInstnId/Othr/Id").text).to eq("NOTPROVIDED")
  end

  describe ".problem_for" do
    it "refuse ce qui ne peut pas partir, en le disant" do
      sans = facture(tiers: ThirdParty.create!(name: "Le Maraîcher", kind: "supplier"))
      faux = facture(tiers: ThirdParty.create!(name: "Faux", kind: "supplier").tap { |t| t.update_column(:iban, "BE68539007547035") })
      suisse = facture(tiers: ThirdParty.create!(name: "Zurich", kind: "supplier", iban: "CH9300762011623852957"))

      expect(described_class.problem_for(facture)).to be_nil
      expect(described_class.problem_for(sans)).to include("Pas d'IBAN")
      expect(described_class.problem_for(faux)).to include("IBAN invalide")
      expect(described_class.problem_for(suisse)).to include("BIC")
    end
  end

  describe "les garde-fous" do
    it "refuse une dette d'une autre structure" do
      srl = build_legal_entity(name: "SRL Domaine", form: "srl")
      build_fiscal_year(srl)
      autre = PurchaseInvoice.create!(legal_entity: srl, third_party: antargaz, number: "S-1",
                                     issued_on: Date.new(2026, 6, 1), total_cents: 1_000)
      autre.purchase_invoice_lines.create!(general_account: charges, amount_cents: 1_000)
      autre = PurchaseInvoices::Advance.new(purchase_invoice: autre).submit!

      expect { fichier([autre]) }.to raise_error(described_class::Error, /autre structure/)
    end

    it "refuse un fichier vide ou une date passée" do
      expect { fichier([]) }.to raise_error(described_class::Error, /au moins un/)
      expect { fichier([facture], execution_date: Date.current - 1) }.to raise_error(described_class::Error, /passée/)
    end
  end
end
