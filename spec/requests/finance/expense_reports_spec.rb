require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 1 — l'écran des notes de frais. La compta encode depuis le
# papier : une feuille de plusieurs lignes recopiée d'une traite, puis deux
# clics pour la passer en traitement.
RSpec.describe "Comptabilité — Notes de frais", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:expense_account) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let(:human) { Human.create!(name: "Sébastien Test", iban: "BE68539007547034") }
  let(:autre) { Human.create!(name: "Aline Test") }

  before { sign_in user }

  def build_report(person: human, status: "recorded", amount_cents: 8_740, kind: "expenses")
    report = ExpenseReport.create!(kind: kind, human: person, legal_entity: entity,
                                   status: status, submitted_on: Date.current)
    report.expense_lines.create!(spent_on: Date.current, label: "Visserie",
                                 amount_cents: amount_cents, general_account: expense_account)
    report.reload
  end

  describe "la liste" do
    it "affiche les notes avec leur total et le reste à payer" do
      build_report
      en_traitement = build_report(person: autre, amount_cents: 2_000)
      ExpenseReports::Process.new(expense_report: en_traitement).run!

      get finance_expense_reports_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sébastien Test")
      expect(response.body).to include("Aline Test")
      expect(response.body).to include("Reste à payer")
    end

    # Les noms des personnes vivent AUSSI dans le sélecteur de filtre : on
    # vérifie donc les lignes du tableau (leur lien vers la fiche), pas le
    # corps de la page.
    def listed?(report) = response.body.include?("/finance/expense_reports/#{report.id}\"")

    it "filtre par statut" do
      brouillon = build_report
      en_traitement = build_report(person: autre)
      ExpenseReports::Process.new(expense_report: en_traitement).run!

      get finance_expense_reports_path(status: "processing")

      expect(listed?(en_traitement)).to be(true)
      expect(listed?(brouillon)).to be(false)
    end

    it "filtre par personne" do
      sienne = build_report
      autres = build_report(person: autre)

      get finance_expense_reports_path(human_id: human.id)

      expect(listed?(sienne)).to be(true)
      expect(listed?(autres)).to be(false)
    end

    it "filtre par période" do
      ancienne = build_report
      ancienne.update!(submitted_on: 3.months.ago.to_date)
      recente = build_report(person: autre)

      get finance_expense_reports_path(from: 1.month.ago.to_date.to_s)

      expect(listed?(recente)).to be(true)
      expect(listed?(ancienne)).to be(false)
    end
  end

  describe "la saisie" do
    it "crée une note de trois lignes en une passe" do
      expect {
        post finance_expense_reports_path, params: {
          expense_report: {
            human_id: human.id, legal_entity_id: entity.id, kind: "expenses",
            submitted_on: Date.current.to_s,
            expense_lines_attributes: {
              "0" => { spent_on: Date.current.to_s, label: "Visserie", supplier_name: "Brico Yvoir",
                       amount_in_euros: "24,90", general_account_id: expense_account.id, doc_kind: "ticket" },
              "1" => { spent_on: Date.current.to_s, label: "Terreau",
                       amount_in_euros: "62,50", general_account_id: expense_account.id },
              "2" => { spent_on: Date.current.to_s, label: "Essence",
                       amount_in_euros: "35,00", general_account_id: expense_account.id }
            }
          }
        }
      }.to change(ExpenseReport, :count).by(1)

      report = ExpenseReport.order(:id).last
      expect(report.expense_lines.count).to eq(3)
      expect(report.total_cents).to eq(12_240)
      expect(report.created_by).to eq(user)
      expect(response).to redirect_to(finance_expense_report_path(report))
    end

    it "refuse une ligne sans compte de charge et réaffiche le formulaire" do
      post finance_expense_reports_path, params: {
        expense_report: {
          human_id: human.id, legal_entity_id: entity.id,
          expense_lines_attributes: { "0" => { spent_on: Date.current.to_s, label: "Sans compte",
                                               amount_in_euros: "10,00" } }
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("obligatoire")
    end

    it "refuse de modifier une note passée en traitement" do
      report = build_report
      ExpenseReports::Process.new(expense_report: report).run!

      get edit_finance_expense_report_path(report)

      expect(response).to redirect_to(finance_expense_report_path(report))
      expect(flash[:alert]).to include("plus modifiable")
    end
  end

  describe "les actions" do
    it "passe la note en traitement : numéro de pièce et écriture" do
      report = build_report

      post start_processing_finance_expense_report_path(report), params: { processed_on: Date.current.to_s }

      report.reload
      expect(report.status).to eq("processing")
      expect(report.reference).to eq("NF-#{Date.current.year}-001")
      expect(report.journal_entry).to be_present
      expect(flash[:notice]).to include(report.reference)
    end

    it "rejette la note avec son motif" do
      report = build_report

      post reject_finance_expense_report_path(report), params: { rejection_reason: "Ticket illisible" }

      expect(report.reload.status).to eq("rejected")
      expect(report.rejection_reason).to eq("Ticket illisible")
    end

    it "refuse un rejet sans motif" do
      report = build_report

      post reject_finance_expense_report_path(report), params: { rejection_reason: "" }

      expect(report.reload.status).to eq("recorded")
      expect(flash[:alert]).to be_present
    end

    it "marque la note payée en espèces" do
      cash_general = build_general_account(code: "570000", name: "Caisse", klass: 5, nature: "asset")
      build_cash_account(entity, cash_general, name: "Caisse du domaine", kind: "cash")
      report = build_report
      ExpenseReports::Process.new(expense_report: report).run!

      post pay_in_cash_finance_expense_report_path(report), params: { paid_on: Date.current.to_s }

      expect(report.reload.status).to eq("paid")
      expect(CashEntry.order(:id).last.amount_cents).to eq(-8_740)
    end

    it "dit ce qui manque quand aucune caisse n'existe" do
      report = build_report
      ExpenseReports::Process.new(expense_report: report).run!

      post pay_in_cash_finance_expense_report_path(report)

      expect(report.reload.status).to eq("processing")
      expect(flash[:alert]).to include("caisse")
    end
  end

  describe "la fiche" do
    it "signale une note dont le bénéficiaire n'a pas d'IBAN" do
      report = build_report(person: autre)

      get finance_expense_report_path(report)

      expect(response.body).to include("Pas d'IBAN sur la fiche")
    end

    it "montre l'IBAN masqué quand il existe" do
      report = build_report

      get finance_expense_report_path(report)

      expect(response.body).to include("7034")
      expect(response.body).not_to include("BE68539007547034")
    end
  end
end
