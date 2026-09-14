require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 2 — le passage d'un statut au suivant, et l'écriture qui naît
# au bon moment.
RSpec.describe PurchaseInvoices::Advance do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:fournisseur) { ThirdParty.create!(name: "Antargaz", kind: "supplier", vat_number: "BE0123456789") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:entretien) { build_general_account(code: "611000", name: "Entretien", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }

  let(:invoice) do
    PurchaseInvoice.create!(legal_entity: entity, third_party: fournisseur, number: "F-2026-1",
                            issued_on: Date.new(2026, 6, 1), total_cents: 12_000)
  end

  def ventile!(*montants)
    montants.each_with_index do |montant, index|
      invoice.purchase_invoice_lines.create!(general_account: index.zero? ? charges : entretien,
                                             team: technique, amount_cents: montant)
    end
    invoice.reload
  end

  describe "#submit!" do
    it "refuse tant que la ventilation ne couvre pas le total" do
      ventile!(5_000)

      expect { described_class.new(purchase_invoice: invoice).submit! }
        .to raise_error(described_class::NotBalanced, /reste/)
    end

    it "passe en « à payer » et génère l'écriture d'achat" do
      ventile!(8_000, 4_000)

      expect {
        described_class.new(purchase_invoice: invoice).submit!
      }.to change { JournalEntry.count }.by(1)

      expect(invoice.reload.status).to eq("to_pay")
      expect(invoice.posted_at).to be_present

      ecriture = JournalEntry.find_by(source: invoice, journal: "purchases")
      expect(ecriture.journal_lines.sum(&:debit_cents)).to eq(12_000)
      expect(ecriture.journal_lines.sum(&:credit_cents)).to eq(12_000)

      credit = ecriture.journal_lines.find { |l| l.credit_cents.positive? }
      expect(credit.general_account).to eq(fournisseurs)
      expect(credit.third_party).to eq(fournisseur)

      debits = ecriture.journal_lines.select { |l| l.debit_cents.positive? }
      expect(debits.map(&:general_account)).to match_array([charges, entretien])
      expect(debits.map(&:team).uniq).to eq([technique])
    end

    # Une facture qui attend l'aval d'un pôle n'est pas une dette : pas
    # d'écriture tant que personne n'a dit oui.
    it "s'arrête en validation quand un pôle doit dire oui, sans écrire" do
      invoice.update!(requires_validation: true, validation_team: technique)
      ventile!(12_000)

      expect {
        described_class.new(purchase_invoice: invoice).submit!
      }.not_to change { JournalEntry.count }

      expect(invoice.reload.status).to eq("to_validate")
      expect(invoice.posted_at).to be_nil
    end

    it "ne recomptabilise pas une facture déjà payable" do
      ventile!(12_000)
      described_class.new(purchase_invoice: invoice).submit!

      expect { described_class.new(purchase_invoice: invoice.reload).submit! }
        .to raise_error(described_class::AlreadyPayable)
    end

    it "sort une facture de la contestation" do
      ventile!(12_000)
      described_class.new(purchase_invoice: invoice).dispute!("Livraison jamais reçue")

      described_class.new(purchase_invoice: invoice.reload).submit!

      expect(invoice.reload.status).to eq("to_pay")
      expect(invoice.dispute_reason).to be_nil
    end
  end

  describe "#dispute!" do
    it "exige un motif" do
      expect { described_class.new(purchase_invoice: invoice).dispute!("") }
        .to raise_error(described_class::MissingReason)
    end

    it "bloque une facture avec son motif" do
      described_class.new(purchase_invoice: invoice).dispute!("Livraison jamais reçue")

      expect(invoice.reload.status).to eq("disputed")
      expect(invoice.dispute_reason).to eq("Livraison jamais reçue")
    end

    it "refuse de contester une facture déjà comptabilisée" do
      ventile!(12_000)
      described_class.new(purchase_invoice: invoice).submit!

      expect { described_class.new(purchase_invoice: invoice.reload).dispute!("Trop tard") }
        .to raise_error(described_class::AlreadyPayable)
    end
  end
end
