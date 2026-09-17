require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 3 — le paiement d'une note de frais.
#
# La note encodée et passée en traitement portait sa dette au grand livre, mais
# nulle part ailleurs : elle n'apparaissait pas devant la trésorière le mercredi
# matin, aucune ligne bancaire ne lui était proposée, et le bénéficiaire
# n'apprenait jamais que l'argent était parti.
RSpec.describe "Comptabilité — paiement d'une note de frais (epic #241, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:charges) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:banque_compte) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
  let!(:banque) { build_cash_account(entity, banque_compte, name: "Triodos", kind: "bank") }

  let!(:beneficiaire) do
    Human.create!(name: "Sébastien Test", email: "sebastien-pay@les4sources.be",
                  status: "active", iban: "BE68539007547034")
  end
  let!(:beneficiaire_user) do
    User.create!(email: "sebastien-pay-user@les4sources.be", password: "password123", human: beneficiaire)
  end
  let(:compta_user) { User.create!(email: "compta-pay@les4sources.be", password: "password123") }

  before do
    ActionMailer::Base.deliveries.clear
    sign_in compta_user
  end

  def note(amount_cents: 8_740, human: beneficiaire)
    report = ExpenseReport.create!(kind: "expenses", human: human, legal_entity: entity,
                                   submitted_on: Date.new(2026, 6, 1))
    report.expense_lines.create!(spent_on: Date.new(2026, 5, 28), label: "Visserie",
                                 amount_cents: amount_cents, general_account: charges)
    report.reload
  end

  def processed(**args)
    report = note(**args)
    ExpenseReports::Process.new(expense_report: report, processed_on: Date.new(2026, 6, 5)).run!
    report.reload
  end

  describe "le contrat Payable" do
    it "dit combien, à qui, sur quel compte, avec quelle communication" do
      report = processed

      expect(report.payable_amount_cents).to eq(8_740)
      expect(report.payable_beneficiary).to eq("Sébastien Test")
      expect(report.payable_iban).to eq("BE68539007547034")
      expect(report.payable_communication).to eq(report.reference)
      expect(report.payable_path).to eq(finance_expense_report_path(report))
    end

    it "prend l'IBAN de la PERSONNE, pas celui du tiers comptable" do
      report = processed
      ThirdParty.for_human!(beneficiaire).update!(iban: "BE62510007547061")

      expect(report.payable_iban).to eq("BE68539007547034")
    end

    it "ne crée aucun tiers en lisant simplement le payable" do
      sans_tiers = Human.create!(name: "Sans tiers", email: "sans-tiers@les4sources.be", status: "active")
      report = processed(human: sans_tiers)

      expect { report.payable_third_party }.not_to change(ThirdParty, :count)
    end

    it "n'est pas prêt à payer sans IBAN, mais ne disparaît pas pour autant" do
      beneficiaire.update!(iban: nil)
      report = processed

      expect(report.payable_ready?).to be(false)
      expect(report.payable_amount_cents).to eq(8_740)
    end
  end

  describe "GET /finance/payables" do
    it "liste les notes en traitement à côté des factures" do
      report = processed

      get finance_payables_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sébastien Test")
      expect(response.body).to include(report.reference)
      expect(response.body).to include("BE68539007547034")
    end

    it "n'y fait pas figurer une note encore à l'état d'enregistrement" do
      report = note

      get finance_payables_path

      expect(response.body).not_to include(report.payable_label)
    end

    it "signale une note dont le bénéficiaire n'a pas d'IBAN" do
      beneficiaire.update!(iban: nil)
      processed

      get finance_payables_path

      expect(response.body).to include("sans IBAN")
    end
  end

  describe "le rapprochement bancaire" do
    let(:report) { processed }

    def sortie(amount_cents: -8_740, iban: nil)
      entry = build_cash_entry(banque, amount_cents: amount_cents,
                               entry_date: Date.new(2026, 6, 20), label: "Virement Sébastien")
      entry.update!(counterparty_iban: iban) if iban
      entry
    end

    it "propose la note dont le montant correspond exactement" do
      report
      entry = sortie

      matches = Finance::MatchExpenseReports.new.for_entry(entry)

      expect(matches.map(&:report)).to eq([report])
      expect(matches.first.confidence).to eq(Finance::MatchExpenseReports::AMOUNT_CONFIDENCE)
    end

    it "préfère la correspondance d'IBAN à celle du montant" do
      report
      entry = sortie(amount_cents: -5_000, iban: "BE68 5390 0754 7034")

      matches = Finance::MatchExpenseReports.new.for_entry(entry)

      expect(matches.first.report).to eq(report)
      expect(matches.first.confidence).to eq(Finance::MatchExpenseReports::IBAN_CONFIDENCE)
      expect(matches.first.reason).to include("Sébastien Test")
    end

    it "ne propose jamais rien sur une ligne entrante" do
      report

      expect(Finance::MatchExpenseReports.new.for_entry(sortie(amount_cents: 8_740))).to be_empty
    end

    it "ne crée AUCUNE allocation en proposant (invariant B4)" do
      report
      entry = sortie

      expect { Finance::MatchExpenseReports.new.for_entry(entry) }
        .not_to change(CashAllocation, :count)
    end

    it "affecte sur le 440000 avec la note en document, et la passe en payée" do
      report
      entry = sortie

      post pay_expense_report_finance_cash_entry_path(entry, expense_report_id: report.id)

      expect(response).to redirect_to(finance_unallocated_cash_entries_path)
      allocation = entry.cash_allocations.reload.first
      expect(allocation.general_account).to eq(fournisseurs)
      expect(allocation.document).to eq(report)
      expect(allocation.third_party).to eq(ThirdParty.find_by(human_id: beneficiaire.id))
      expect(allocation.amount_cents).to eq(-8_740)

      expect(report.reload.status).to eq("paid")
      expect(report.paid_on).to eq(Date.new(2026, 6, 20))
    end

    it "redevient à payer si on défait l'affectation" do
      report
      entry = sortie
      post pay_expense_report_finance_cash_entry_path(entry, expense_report_id: report.id)
      expect(report.reload.status).to eq("paid")

      # La ligne est passée au grand livre : on contre-passe avant de défaire
      # l'affectation, comme le ferait l'écran « Annuler la passation ».
      Accounting::UnpostCashEntry.new(cash_entry: entry.reload).run!
      entry.cash_allocations.reload.each(&:destroy!)

      expect(report.reload.status).to eq("processing")
      expect(report.paid_on).to be_nil
    end

    it "refuse de rapprocher une note qui n'est pas en traitement" do
      brouillon = note
      entry = sortie

      post pay_expense_report_finance_cash_entry_path(entry, expense_report_id: brouillon.id)

      expect(response).to redirect_to(finance_cash_entry_path(entry))
      expect(entry.cash_allocations.reload).to be_empty
    end

    it "refuse de surpayer une note" do
      report
      entry = build_cash_entry(banque, amount_cents: -20_000, entry_date: Date.new(2026, 6, 20),
                               label: "Virement groupé")

      post pay_expense_report_finance_cash_entry_path(entry, expense_report_id: report.id, amount: "150,00")

      expect(response).to redirect_to(finance_cash_entry_path(entry))
      expect(entry.cash_allocations.reload).to be_empty
    end

    it "laisse une note partiellement rapprochée en traitement" do
      report
      entry = build_cash_entry(banque, amount_cents: -20_000, entry_date: Date.new(2026, 6, 20),
                               label: "Virement groupé")

      post pay_expense_report_finance_cash_entry_path(entry, expense_report_id: report.id, amount: "40,00")

      expect(report.reload.status).to eq("processing")
      expect(report.partially_paid?).to be(true)
    end
  end

  describe "l'email au bénéficiaire" do
    it "part une seule fois, avec le détail des lignes" do
      report = processed
      entry = build_cash_entry(banque, amount_cents: -8_740, entry_date: Date.new(2026, 6, 20),
                               label: "Virement Sébastien")

      post pay_expense_report_finance_cash_entry_path(entry, expense_report_id: report.id)

      mail = ActionMailer::Base.deliveries.find { |m| m.to&.include?("sebastien-pay@les4sources.be") }
      expect(mail).to be_present
      expect(mail.subject).to include(report.reference)
      expect(mail.subject).to include("87,40")
      expect(mail.body.encoded).to include("Visserie")
      expect(report.reload.paid_notified_at).to be_present
    end

    it "ne se rejoue pas après un aller-retour de statut" do
      report = processed
      entry = build_cash_entry(banque, amount_cents: -8_740, entry_date: Date.new(2026, 6, 20),
                               label: "Virement Sébastien")
      post pay_expense_report_finance_cash_entry_path(entry, expense_report_id: report.id)
      envoyes = ActionMailer::Base.deliveries.size

      Accounting::UnpostCashEntry.new(cash_entry: entry.reload).run!
      entry.cash_allocations.reload.each(&:destroy!)
      entry2 = build_cash_entry(banque, amount_cents: -8_740, entry_date: Date.new(2026, 6, 25),
                                label: "Virement Sébastien bis")
      post pay_expense_report_finance_cash_entry_path(entry2, expense_report_id: report.reload.id)

      expect(report.reload.status).to eq("paid")
      expect(ActionMailer::Base.deliveries.size).to eq(envoyes)
    end

    it "ne part pas vers un bénéficiaire sans adresse" do
      sans_email = Human.create!(name: "Sans email", status: "active", iban: "BE68539007547034")
      report = processed(human: sans_email)
      entry = build_cash_entry(banque, amount_cents: -8_740, entry_date: Date.new(2026, 6, 20),
                               label: "Virement")

      expect {
        post pay_expense_report_finance_cash_entry_path(entry, expense_report_id: report.id)
      }.not_to raise_error

      expect(report.reload.status).to eq("paid")
      expect(report.paid_notified_at).to be_nil
    end
  end
end
