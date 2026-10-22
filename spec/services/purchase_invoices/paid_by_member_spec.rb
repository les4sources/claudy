require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# « Payée par un membre » (Michael, 2026-10-22) — la facture AliFar de 24 € est
# payée en magasin par un membre qui se la fait rembourser. La note de frais
# porte la charge ; la facture n'en est que le justificatif et ne passe jamais
# au journal des achats, sans quoi l'achat compterait deux fois.
RSpec.describe PurchaseInvoices::PaidByMember do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:materiel) { build_general_account(code: "601101", name: "Matériel Pôle Animaux", klass: 6, nature: "expense") }
  let(:pole) { Team.create!(name: "Pôle Micro-ferme") }
  let(:alifar) { ThirdParty.create!(name: "AliFar", kind: "supplier") }
  let(:membre) { Human.create!(name: "Marie Test", iban: "BE68539007547034") }

  let(:facture) do
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: alifar, number: "INV/26-27/1791",
                                issued_on: Date.new(2026, 10, 20), total_cents: 2_400)
    f.purchase_invoice_lines.create!(general_account: materiel, team: pole, amount_cents: 2_400,
                                     label: "Equidigest + bonbon")
    f.document.attach(io: StringIO.new("%PDF-1.4 facture"), filename: "alifar.pdf", content_type: "application/pdf")
    f.save!
    f.reload
  end

  it "ouvre une note de frais au membre, avec la dépense, son compte, son pôle et la pièce" do
    note = described_class.new(purchase_invoice: facture, human: membre).run!

    expect(note).to be_recorded
    expect(note.human).to eq(membre)
    expect(note.legal_entity).to eq(entity)
    ligne = note.expense_lines.sole
    expect(ligne.amount_cents).to eq(2_400)
    expect(ligne.general_account).to eq(materiel)
    expect(ligne.team).to eq(pole)
    expect(ligne.label).to eq("Equidigest + bonbon")
    expect(ligne.supplier_name).to eq("AliFar")
    expect(ligne.spent_on).to eq(Date.new(2026, 10, 20))
    expect(ligne.purchase_invoice).to eq(facture)
    expect(ligne.receipt.blob).to eq(facture.document.blob)
    expect(facture.reload).to be_member_paid
  end

  it "ajoute la dépense à la note encore enregistrée du membre" do
    ouverte = ExpenseReport.create!(kind: "expenses", human: membre, legal_entity: entity, submitted_on: Date.new(2026, 10, 1))
    ouverte.expense_lines.create!(spent_on: Date.new(2026, 10, 2), label: "Clous", amount_cents: 500, receipt_on_paper: true)

    note = described_class.new(purchase_invoice: facture, human: membre).run!

    expect(note).to eq(ouverte)
    expect(note.expense_lines.count).to eq(2)
    expect(note.total_cents).to eq(2_900)
  end

  it "relie la dépense que le membre a déjà déclarée, sans rien ajouter" do
    note = ExpenseReport.create!(kind: "expenses", human: membre, legal_entity: entity, submitted_on: Date.new(2026, 10, 21))
    ticket = note.expense_lines.create!(spent_on: Date.new(2026, 10, 20), label: "Vermifuge ânes", amount_cents: 2_400,
                                        receipt_on_paper: true)

    expect(described_class.candidate_lines(facture)).to contain_exactly(ticket)
    expect { described_class.new(purchase_invoice: facture, expense_line: ticket).run! }.not_to change(ExpenseLine, :count)

    expect(ticket.reload.purchase_invoice).to eq(facture)
    expect(facture.reload).to be_member_paid
  end

  it "refuse une dépense d'un autre montant" do
    note = ExpenseReport.create!(kind: "expenses", human: membre, legal_entity: entity, submitted_on: Date.new(2026, 10, 21))
    autre = note.expense_lines.create!(spent_on: Date.new(2026, 10, 20), label: "Foin", amount_cents: 3_000, receipt_on_paper: true)

    expect { described_class.new(purchase_invoice: facture, expense_line: autre).run! }
      .to raise_error(described_class::LineNotEligible)
    expect(facture.reload).to be_to_process
  end

  it "ne comptabilise la charge qu'une fois : par la note, jamais par la facture" do
    note = described_class.new(purchase_invoice: facture, human: membre).run!
    ExpenseReports::Process.new(expense_report: note, processed_on: Date.new(2026, 10, 22)).run!

    expect(JournalEntry.where(source: facture)).to be_empty
    charges = JournalLine.where(general_account: materiel)
    expect(charges.sum(:debit_cents)).to eq(2_400)
    expect(charges.sole.team).to eq(pole)
  end

  it "refuse une facture déjà comptabilisée" do
    PurchaseInvoices::Advance.new(purchase_invoice: facture).submit!

    expect { described_class.new(purchase_invoice: facture, human: membre).run! }
      .to raise_error(described_class::BadStatus, /comptabilisée/)
  end

  it "empêche ensuite de l'envoyer au paiement" do
    described_class.new(purchase_invoice: facture, human: membre).run!

    expect { PurchaseInvoices::Advance.new(purchase_invoice: facture).submit! }
      .to raise_error(PurchaseInvoices::Advance::AlreadyPayable, /payée par un membre/)
    expect(JournalEntry.where(source: facture)).to be_empty
  end

  it "se défait en la remettant en traitement, la dépense restant sur la note" do
    note = described_class.new(purchase_invoice: facture, human: membre).run!

    PurchaseInvoices::Advance.new(purchase_invoice: facture).reopen!

    expect(facture.reload).to be_to_process
    expect(note.expense_lines.sole.purchase_invoice_id).to be_nil
  end

  it "rend la facture à la comptabilité quand la ligne est retirée de la note" do
    note = described_class.new(purchase_invoice: facture, human: membre).run!

    note.expense_lines.sole.destroy!

    expect(facture.reload).to be_to_process
  end

  it "exige un membre quand aucune dépense n'est choisie" do
    expect { described_class.new(purchase_invoice: facture).run! }.to raise_error(described_class::MissingMember)
  end
end
