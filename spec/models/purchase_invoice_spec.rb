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

  describe "TVA des lignes tapées HTVA" do
    it "ajoute la TVA au HTVA pour couvrir le total TVAC (facture 2026-014 du Domaine)" do
      invoice = build_invoice(total_cents: 143_882)
      invoice.purchase_invoice_lines.build(general_account: charges, net_cents: 118_911, vat_rate: 21)
      invoice.save!

      line = invoice.purchase_invoice_lines.first
      expect([line.vat_cents, line.amount_cents, line.net_amount_cents]).to eq([24_971, 143_882, 118_911])
      expect(invoice).to be_balanced
    end

    it "calcule la TVA taux par taux sur la somme des bases, comme la pièce" do
      invoice = build_invoice(total_cents: 0)
      # 2 × 0,07 € à 21 % : ligne à ligne 0,01 + 0,01 ; sur la base de
      # 0,14 €, 0,03 €. C'est la seconde qui figure sur la pièce.
      2.times { invoice.purchase_invoice_lines.build(general_account: charges, net_cents: 7, vat_rate: 21) }
      invoice.purchase_invoice_lines.build(general_account: charges, net_cents: 10_000, vat_rate: 6)
      invoice.total_cents = 14 + 3 + 10_000 + 600
      invoice.save!

      expect(invoice.lines_vat_cents).to eq(603)
      expect(invoice).to be_balanced
    end

    it "extrait la TVA d'une ligne tapée TVA comprise, sans toucher à son montant (ticket des 3 Petits Pois)" do
      invoice = build_invoice(total_cents: 12_778)
      invoice.purchase_invoice_lines.build(general_account: charges, gross_cents: 12_778, vat_rate: 6, label: "reBEL sel de mer")
      invoice.save!

      line = invoice.purchase_invoice_lines.first
      expect([line.amount_cents, line.vat_cents, line.net_amount_cents]).to eq([12_778, 723, 12_055])
      expect(invoice).to be_balanced
    end

    it "extrait la TVA taux par taux sur la somme des montants TVAC" do
      # 2 × 0,10 € TVAC à 21 % : ligne à ligne 0,02 + 0,02 ; sur 0,20 €, 0,03 €.
      invoice = build_invoice(total_cents: 20 + 16_051)
      2.times { invoice.purchase_invoice_lines.build(general_account: charges, gross_cents: 10, vat_rate: 21) }
      invoice.purchase_invoice_lines.build(general_account: charges, gross_cents: 16_051, vat_rate: 6)
      invoice.save!

      expect(invoice.lines_vat_cents).to eq(3 + 909)
      expect(invoice.lines_total_cents).to eq(invoice.total_cents)
    end

    it "laisse tel quel un montant donné sans HTVA (outil MCP, pièce lue d'un mail)" do
      invoice = build_invoice
      invoice.purchase_invoice_lines.build(general_account: charges, amount_cents: 12_000)
      invoice.save!

      expect(invoice.purchase_invoice_lines.first.attributes.slice("amount_cents", "vat_cents"))
        .to eq("amount_cents" => 12_000, "vat_cents" => 0)
    end
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

  describe "communication de paiement" do
    def facture(ref) = PurchaseInvoice.new(legal_entity: entity, third_party: fournisseur, number: "F-9",
                                           issued_on: Date.current, total_cents: 1_000, payment_reference: ref)

    it "range une communication structurée sous sa forme canonique" do
      f = facture(" ***000/0024/11862*** ")
      f.valid?
      expect(f.payment_reference).to eq("+++000/0024/11862+++")
    end

    it "refuse douze chiffres dont la clé modulo 97 est fausse" do
      f = facture("+++090/1234/56789+++")
      expect(f).not_to be_valid
      expect(f.errors[:payment_reference].join).to include("clé de contrôle")
    end

    it "garde une communication libre telle quelle, et retombe sur le numéro sans communication" do
      expect(facture("Réf. client 4 Sources").tap(&:valid?).payable_communication).to eq("Réf. client 4 Sources")
      expect(facture("").tap(&:valid?).payable_communication).to eq("F-9")
    end
  end
end
