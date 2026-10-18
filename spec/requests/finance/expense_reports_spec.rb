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
                                 amount_cents: amount_cents, general_account: expense_account, receipt_on_paper: true)
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
    # Depuis le tableau de bord d'un membre (Michael 2026-10-17) : le
    # bénéficiaire arrive dans l'adresse et le formulaire le présélectionne.
    it "présélectionne le bénéficiaire venu du tableau de bord" do
      autre
      get new_finance_expense_report_path(kind: "mileage", human_id: human.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<option selected="selected" value="#{human.id}">Sébastien Test</)
    end

    it "laisse le bénéficiaire vide sans human_id, ou quand il ne désigne personne" do
      human
      get new_finance_expense_report_path(human_id: 0)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('selected="selected" value="' + human.id.to_s + '"')
    end

    it "crée une note de trois lignes en une passe" do
      expect {
        post finance_expense_reports_path, params: {
          expense_report: {
            human_id: human.id, legal_entity_id: entity.id, kind: "expenses",
            submitted_on: Date.current.to_s,
            expense_lines_attributes: {
              "0" => { spent_on: Date.current.to_s, label: "Visserie", supplier_name: "Brico Yvoir",
                       amount_in_euros: "24,90", doc_kind: "ticket",
                       receipt: fixture_file_upload(Rails.root.join("spec/fixtures/files/ticket.pdf"), "application/pdf") },
              "1" => { spent_on: Date.current.to_s, label: "Terreau",
                       amount_in_euros: "62,50", receipt_on_paper: "1" },
              "2" => { spent_on: Date.current.to_s, label: "Essence",
                       amount_in_euros: "35,00", receipt_on_paper: "1" }
            }
          }
        }
      }.to change(ExpenseReport, :count).by(1)

      report = ExpenseReport.order(:id).last
      expect(report.expense_lines.count).to eq(3)
      expect(report.total_cents).to eq(12_240)
      expect(report.created_by).to eq(user)
      expect(report.expense_lines.map(&:general_account_id)).to all(be_nil)
      expect(report.expense_lines.find_by(label: "Visserie").receipt).to be_attached
      expect(response).to redirect_to(finance_expense_report_path(report))
    end

    # Michael, 2026-10-18 : celui qui saisit ne choisit pas le compte.
    it "ne propose pas de compte de charge, et ignore un compte forgé" do
      get new_finance_expense_report_path(kind: "expenses")
      expect(response.body).not_to include("general_account_id")
      expect(response.body).to include("Fourni sur papier")

      post finance_expense_reports_path, params: {
        expense_report: {
          human_id: human.id, legal_entity_id: entity.id,
          expense_lines_attributes: { "0" => { spent_on: Date.current.to_s, label: "Forgé", amount_in_euros: "10,00",
                                               general_account_id: expense_account.id, receipt_on_paper: "1" } }
        }
      }

      expect(ExpenseReport.order(:id).last.expense_lines.sole.general_account_id).to be_nil
    end

    it "refuse une dépense sans justificatif ni mention papier" do
      expect {
        post finance_expense_reports_path, params: {
          expense_report: {
            human_id: human.id, legal_entity_id: entity.id,
            expense_lines_attributes: { "0" => { spent_on: Date.current.to_s, label: "Sans ticket",
                                                 amount_in_euros: "10,00" } }
          }
        }
      }.not_to change(ExpenseReport, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(CGI.unescapeHTML(response.body)).to include("Fourni sur papier")
    end

    # Sentry CLAUDY-86 : un formulaire refusé avec un ticket joint tombait en
    # 500 — le lien vers un fichier jamais enregistré n'existe pas.
    it "réaffiche un formulaire refusé qui portait un ticket, sans erreur" do
      post finance_expense_reports_path, params: {
        expense_report: {
          human_id: "", legal_entity_id: entity.id,
          expense_lines_attributes: {
            "0" => { spent_on: Date.current.to_s, label: "Visserie", amount_in_euros: "10,00",
                     receipt: fixture_file_upload(Rails.root.join("spec/fixtures/files/ticket.pdf"), "application/pdf") }
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(CGI.unescapeHTML(response.body)).to include("« ticket.pdf » n'a pas été enregistré")
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

    describe "l'attribution des comptes au traitement" do
      let!(:fournitures) { build_general_account(code: "604000", name: "Fournitures", klass: 6, nature: "expense") }

      def sans_compte
        report = build_report
        report.expense_lines.update_all(general_account_id: nil)
        report.reload
      end

      it "propose un compte par ligne sur la fiche d'une note enregistrée" do
        report = sans_compte
        line = report.expense_lines.sole

        get finance_expense_report_path(report)

        expect(response.body).to include(%(name="accounts[#{line.id}]"), 'form="traitement-note"')
        expect(CGI.unescapeHTML(response.body)).to include("1 à attribuer")
      end

      it "enregistre le compte choisi et passe la note en traitement" do
        report = sans_compte
        line = report.expense_lines.sole

        post start_processing_finance_expense_report_path(report),
             params: { processed_on: Date.current.to_s, accounts: { line.id.to_s => fournitures.id.to_s } }

        expect(report.reload.status).to eq("processing")
        expect(line.reload.general_account).to eq(fournitures)
        expect(report.journal_entry.journal_lines.map { |l| l.general_account.code }).to include("604000")
      end

      it "refuse de traiter une ligne sans compte, et le dit" do
        report = sans_compte

        post start_processing_finance_expense_report_path(report), params: { processed_on: Date.current.to_s }

        expect(report.reload.status).to eq("recorded")
        expect(flash[:alert]).to include("Attribue un compte de charge", "Visserie")
      end

      it "refuse un compte qui n'est ni une charge ni une immobilisation" do
        report = sans_compte
        line = report.expense_lines.sole

        post start_processing_finance_expense_report_path(report),
             params: { accounts: { line.id.to_s => supplier_account.id.to_s } }

        expect(report.reload.status).to eq("recorded")
        expect(line.reload.general_account_id).to be_nil
        expect(flash[:alert]).to include("compte de charge")
      end
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
