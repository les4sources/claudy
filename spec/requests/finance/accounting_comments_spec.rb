require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #242, phase 3 — les commentaires et les notifications branchés sur la
# comptabilité.
#
# Le point : une note de frais bloquée parce qu'il manque un ticket reste
# bloquée tant que personne ne le DIT quelque part de visible. Jusqu'ici ça se
# disait dans une boîte mail, donc nulle part.
RSpec.describe "Comptabilité — commentaires et notifications", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:charges) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:caisse_compte) { build_general_account(code: "570000", name: "Caisse", klass: 5, nature: "asset") }
  let!(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse bar", kind: "cash") }

  let!(:beneficiaire) { Human.create!(name: "Sébastien Test", email: "sebastien@les4sources.be", status: "active") }
  let!(:beneficiaire_user) { User.create!(email: "sebastien-user@les4sources.be", password: "password123", human: beneficiaire) }
  let(:compta_user) { User.create!(email: "compta@les4sources.be", password: "password123") }

  before do
    Setting.set("accounting_notification_emails", "compta@les4sources.be")
    compta_user
    ActionMailer::Base.deliveries.clear
    sign_in compta_user
  end

  def note(**attrs)
    report = ExpenseReport.create!({ kind: "expenses", human: beneficiaire, legal_entity: entity,
                                     submitted_on: Date.new(2026, 6, 1) }.merge(attrs))
    report.expense_lines.create!(spent_on: Date.new(2026, 5, 28), label: "Visserie",
                                 amount_cents: 2_490, general_account: charges)
    report.reload
  end

  describe "les notes de frais sont commentables" do
    it "rend le fil sur la fiche" do
      report = note

      get finance_expense_report_path(report)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Comment.thread_dom_id(report))
    end

    it "accepte un commentaire sur une note" do
      report = note

      expect {
        post comments_path, params: {
          comment: { commentable_type: "ExpenseReport", commentable_id: report.id,
                     body: "Il manque le ticket du 12/08." }
        }
      }.to change(Comment, :count).by(1)

      expect(report.comments.count).to eq(1)
    end

    it "prévient le bénéficiaire et la comptabilité" do
      report = note
      Comment.create!(commentable: report, author: compta_user, body: "Première question")

      expect {
        post comments_path, params: {
          comment: { commentable_type: "ExpenseReport", commentable_id: report.id,
                     body: "Et le ticket du 15 ?" }
        }
      }.to change { beneficiaire_user.notifications.count }.by(1)
    end

    # `polymorphic_path(report)` donnerait `/expense_reports/:id`, qui n'existe
    # pas : la notification tombait silencieusement sur « / ».
    it "pointe vers la fiche SOUS le namespace finance, pas vers la racine" do
      report = note

      post comments_path, params: {
        comment: { commentable_type: "ExpenseReport", commentable_id: report.id, body: "Question" }
      }

      notification = beneficiaire_user.notifications.order(:id).last
      expect(notification.url).to start_with(finance_expense_report_path(report))
      expect(notification.url).not_to eq("/")
    end
  end

  describe "« Demander une info »" do
    it "propose le raccourci quand le bénéficiaire a un compte" do
      report = note

      get finance_expense_report_path(report)

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Demander une info")
      expect(body).to include('name="info_request"')
    end

    it "ne le propose pas quand le bénéficiaire n'a pas de compte" do
      orphelin = Human.create!(name: "Sans Compte", status: "active")
      report = ExpenseReport.create!(kind: "expenses", human: orphelin, legal_entity: entity,
                                     submitted_on: Date.new(2026, 6, 1))
      report.expense_lines.create!(spent_on: Date.new(2026, 5, 28), label: "Visserie",
                                   amount_cents: 2_490, general_account: charges)

      get finance_expense_report_path(report.reload)

      expect(CGI.unescapeHTML(response.body)).not_to include("Demander une info")
    end

    it "pose un commentaire ET interpelle nommément le bénéficiaire" do
      report = note

      post comments_path, params: {
        info_request: "1",
        comment: { commentable_type: "ExpenseReport", commentable_id: report.id,
                   body: "Il manque le ticket du 12/08 — tu l'as ?" }
      }

      expect(report.comments.count).to eq(1)
      kinds = beneficiaire_user.notifications.pluck(:kind)
      expect(kinds).to include("info_requested")
      demande = beneficiaire_user.notifications.find_by(kind: "info_requested")
      expect(demande.title).to include("Information demandée")
      expect(demande.body).to include("ticket du 12/08")
    end

    it "n'interpelle personne sans le drapeau" do
      report = note

      post comments_path, params: {
        comment: { commentable_type: "ExpenseReport", commentable_id: report.id, body: "Note pour moi" }
      }

      expect(beneficiaire_user.notifications.where(kind: "info_requested")).to be_empty
    end
  end

  describe "la note payée" do
    it "notifie le bénéficiaire quel que soit le chemin vers « payée »" do
      report = note
      ExpenseReports::Process.new(expense_report: report, processed_on: Date.new(2026, 6, 5)).run!

      expect {
        ExpenseReports::PayInCash.new(expense_report: report.reload, paid_on: Date.new(2026, 6, 10),
                                      cash_account: caisse).run!
      }.to change { beneficiaire_user.notifications.where(kind: "expense_report_paid").count }.by(1)

      notification = beneficiaire_user.notifications.find_by(kind: "expense_report_paid")
      expect(notification.title).to include("24,90 €")
      expect(notification.url).to start_with(finance_expense_report_path(report))
    end

    it "ne notifie pas deux fois une note déjà payée" do
      report = note
      ExpenseReports::Process.new(expense_report: report, processed_on: Date.new(2026, 6, 5)).run!
      ExpenseReports::PayInCash.new(expense_report: report.reload, paid_on: Date.new(2026, 6, 10),
                                    cash_account: caisse).run!

      expect {
        report.reload.update!(paid_on: Date.new(2026, 6, 11))
      }.not_to change { beneficiaire_user.notifications.where(kind: "expense_report_paid").count }
    end
  end

  describe "les factures d'achat" do
    let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", vat_number: "BE0123456789") }
    let!(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }
    let!(:sourcier) { Human.create!(name: "Martin", email: "martin@les4sources.be", status: "active") }
    let!(:membership) { TeamMembership.create!(team: technique, human: sourcier) }
    let!(:sourcier_user) { User.create!(email: "martin-user@les4sources.be", password: "password123", human: sourcier) }

    def facture(status: nil)
      invoice = PurchaseInvoice.create!(legal_entity: entity, third_party: antargaz, number: "F-#{rand(10_000)}",
                                        issued_on: Date.new(2026, 6, 1), total_cents: 12_000,
                                        requires_validation: true, validation_team: technique)
      invoice.purchase_invoice_lines.create!(general_account: charges, team: technique, amount_cents: 12_000)
      invoice.update_column(:status, status) if status
      invoice.reload
    end

    it "rend le fil sur la fiche" do
      invoice = facture

      get finance_purchase_invoice_path(invoice)

      expect(response.body).to include(Comment.thread_dom_id(invoice))
    end

    it "notifie les membres du pôle QUI ONT UN COMPTE au passage en « À valider »" do
      invoice = facture

      expect {
        PurchaseInvoices::Advance.new(purchase_invoice: invoice, whodunnit: "spec").submit!
      }.to change { sourcier_user.notifications.where(kind: "purchase_invoice_to_validate").count }.by(1)

      notification = sourcier_user.notifications.find_by(kind: "purchase_invoice_to_validate")
      expect(notification.title).to include("Antargaz", "120 €")
      expect(notification.url).to start_with(finance_purchase_invoice_path(invoice))
    end

    it "ne notifie personne quand aucun membre du pôle n'a de compte" do
      muet = Team.create!(name: "Pôle Muet", kind: "economic")
      sans_compte = Human.create!(name: "Sans Compte 2", email: "sc2@les4sources.be", status: "active")
      TeamMembership.create!(team: muet, human: sans_compte)
      invoice = facture
      invoice.update_columns(validation_team_id: muet.id)

      expect {
        PurchaseInvoices::Advance.new(purchase_invoice: invoice.reload, whodunnit: "spec").submit!
      }.not_to change(Notification, :count)
    end

    it "commente une facture et prévient le pôle" do
      invoice = facture(status: "to_validate")

      expect {
        post comments_path, params: {
          comment: { commentable_type: "PurchaseInvoice", commentable_id: invoice.id,
                     body: "Le montant ne colle pas au devis." }
        }
      }.to change { sourcier_user.notifications.where(kind: "comment").count }.by(1)
    end
  end

  # Le garde-fou de l'epic : la liste blanche, pas un `constantize` libre.
  it "refuse un type qui n'est pas dans la liste blanche" do
    post comments_path, params: {
      comment: { commentable_type: "User", commentable_id: compta_user.id, body: "Forgé" }
    }

    expect(response).to have_http_status(:not_found)
  end
end
