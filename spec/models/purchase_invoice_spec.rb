require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 2 — ce qu'une facture d'achat refuse.
RSpec.describe PurchaseInvoice do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fournisseur) { ThirdParty.create!(name: "Antargaz", kind: "supplier", vat_number: "BE0123456789") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }

  def build_invoice(attributes = {})
    described_class.new({ legal_entity: entity, third_party: fournisseur, number: "F-2026-1",
                          issued_on: Date.new(2026, 6, 1), total_cents: 12_000 }.merge(attributes))
  end

  it "accepte une facture sans ligne tant qu'elle est à traiter" do
    expect(build_invoice).to be_valid
  end

  it "refuse un total nul" do
    expect(build_invoice(total_cents: 0)).not_to be_valid
  end

  it "refuse de quitter « à traiter » si les lignes ne couvrent pas le total" do
    invoice = build_invoice
    invoice.save!
    invoice.purchase_invoice_lines.create!(general_account: charges, amount_cents: 5_000)

    invoice.status = "to_pay"

    expect(invoice).not_to be_valid
    expect(invoice.errors[:base].join).to include("couvrir exactement le total")
  end

  it "laisse passer quand les lignes couvrent le total" do
    invoice = build_invoice
    invoice.save!
    invoice.purchase_invoice_lines.create!(general_account: charges, amount_cents: 12_000)

    expect(invoice.reload.tap { |i| i.status = "to_pay" }).to be_valid
  end

  it "refuse un même numéro chez le même fournisseur" do
    build_invoice.save!

    expect(build_invoice(issued_on: Date.new(2026, 7, 1))).not_to be_valid
  end

  it "laisse le même numéro chez deux fournisseurs" do
    build_invoice.save!
    autre = ThirdParty.create!(name: "Luminus", kind: "supplier")

    expect(build_invoice(third_party: autre)).to be_valid
  end

  it "refuse une pièce déjà déposée" do
    build_invoice(pdf_sha256: "abc123").save!

    expect(build_invoice(number: "F-2026-2", pdf_sha256: "abc123")).not_to be_valid
  end

  it "exige un motif pour contester" do
    expect(build_invoice(status: "disputed")).not_to be_valid
    expect(build_invoice(status: "disputed", dispute_reason: "Livraison jamais reçue")).to be_valid
  end

  # Une facture comptabilisée ne se retouche pas : on contre-passe.
  it "gèle son contenu dès qu'elle est payable" do
    invoice = build_invoice
    invoice.save!
    invoice.purchase_invoice_lines.create!(general_account: charges, amount_cents: 12_000)
    invoice.reload.update!(status: "to_pay")

    invoice.total_cents = 99_000

    expect(invoice).not_to be_valid
    expect(invoice.errors[:base].join).to include("contre-passation")
  end

  describe "les drapeaux qualité" do
    it "signale un tiers sans numéro de TVA sans rien bloquer" do
      fournisseur.update!(vat_number: nil)
      invoice = build_invoice
      invoice.save!

      expect(invoice.quality_flags).to include("no_vat_number")
      expect(invoice).to be_valid
    end

    it "signale une facture sans numéro" do
      invoice = build_invoice(number: nil)
      invoice.save!

      expect(invoice.quality_flags).to include("no_number")
    end
  end

  describe "le garde des 5 000 €" do
    it "prévient au-delà, pas en-deçà" do
      expect(build_invoice(total_cents: 499_999).double_signature?).to be(false)
      expect(build_invoice(total_cents: 500_000).double_signature?).to be(true)
    end
  end

  describe "l'étape suivante" do
    it "passe par la validation quand un pôle doit dire oui" do
      expect(build_invoice(requires_validation: true).next_status).to eq("to_validate")
    end

    it "va droit au paiement sinon" do
      expect(build_invoice.next_status).to eq("to_pay")
    end

    it "ne repasse pas par la validation une fois validée" do
      expect(build_invoice(requires_validation: true, validated_at: Time.current).next_status).to eq("to_pay")
    end
  end
end
