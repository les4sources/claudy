require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 2 — les notes de MISSION dans les écrans.
RSpec.describe "Comptabilité > Notes de mission", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-mission@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:societe) { build_legal_entity(name: "Société simple immobilière", form: "simple_company") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:travel) { build_general_account(code: GeneralAccount::TRAVEL_CODE, name: "Déplacements", klass: 6, nature: "expense") }
  let!(:other_account) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:team) { Team.create!(name: "Pôle Nature") }
  let!(:human) { Human.create!(name: "Sébastien Test") }

  before { sign_in user }

  def mission(**attrs)
    report = ExpenseReport.create!({ kind: "mileage", human: human, legal_entity: entity,
                                     submitted_on: Date.new(2026, 6, 1) }.merge(attrs))
    report.expense_lines.create!(spent_on: Date.new(2026, 5, 28), label: "Yvoir → Gembloux",
                                 supplier_name: "CRA-W", distance_km: 84,
                                 general_account: travel, team: team)
    report.reload
  end

  describe "le formulaire dédié" do
    it "propose des kilomètres, pas des euros, et prérempli le compte Déplacements" do
      get new_finance_expense_report_path(kind: "mileage")

      body = CGI.unescapeHTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(body).to include("Les trajets", "Trajet ou motif", "Kilomètres")
      expect(body).not_to include("Montant € *")
      # Le compte « Déplacements » est sélectionné d'office.
      expect(body).to match(/<option selected="selected" value="#{travel.id}"/)
    end

    it "garde le formulaire des frais pour une note de frais" do
      get new_finance_expense_report_path(kind: "expenses")

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Les dépenses", "Montant € *")
      expect(body).not_to include("Trajet ou motif")
    end

    it "crée une note de mission depuis les kilomètres saisis" do
      expect {
        post finance_expense_reports_path, params: {
          expense_report: {
            kind: "mileage", human_id: human.id, legal_entity_id: entity.id,
            submitted_on: "2026-06-01",
            expense_lines_attributes: {
              "0" => { spent_on: "2026-05-28", label: "Yvoir → Gembloux", supplier_name: "CRA-W",
                       distance_in_km: "84", general_account_id: travel.id, team_id: team.id }
            }
          }
        }
      }.to change(ExpenseReport, :count).by(1)

      report = ExpenseReport.order(:id).last
      line = report.expense_lines.sole
      expect(report.kind).to eq("mileage")
      expect(line.distance_km).to eq(84)
      expect(line.rate_cents_per_km).to eq(47)
      expect(report.total_cents).to eq(3_948)
    end

    it "accepte les kilomètres tapés avec une virgule" do
      post finance_expense_reports_path, params: {
        expense_report: {
          kind: "mileage", human_id: human.id, legal_entity_id: entity.id, submitted_on: "2026-06-01",
          expense_lines_attributes: {
            "0" => { spent_on: "2026-05-28", label: "Yvoir → Namur", distance_in_km: "12,5",
                     general_account_id: travel.id }
          }
        }
      }

      expect(ExpenseReport.order(:id).last.expense_lines.sole.distance_km).to eq(12.5)
    end

    it "refuse une ligne de mission sans kilomètres" do
      expect {
        post finance_expense_reports_path, params: {
          expense_report: {
            kind: "mileage", human_id: human.id, legal_entity_id: entity.id, submitted_on: "2026-06-01",
            expense_lines_attributes: {
              "0" => { spent_on: "2026-05-28", label: "Yvoir → Namur", general_account_id: travel.id }
            }
          }
        }
      }.not_to change(ExpenseReport, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "ne laisse pas basculer le type en cours de saisie" do
      get new_finance_expense_report_path(kind: "mileage")

      # Le type est affiché et posté en hidden : basculer au milieu d'une saisie
      # laisserait des lignes orphelines de leur nature.
      hidden = response.body[/<input[^>]*name="expense_report\[kind\]"[^>]*>/]
      expect(hidden).to include('type="hidden"', 'value="mileage"')
      expect(response.body).not_to match(/<select[^>]*name="expense_report\[kind\]"/)
    end
  end

  describe "la liste" do
    it "distingue frais et missions, et les filtre" do
      mission
      frais = ExpenseReport.create!(kind: "expenses", human: human, legal_entity: entity,
                                    submitted_on: Date.new(2026, 6, 2))
      frais.expense_lines.create!(spent_on: Date.new(2026, 5, 30), label: "Visserie",
                                  amount_cents: 2_490, general_account: other_account)

      get finance_expense_reports_path(kind: "mileage")
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Note de mission")
      expect(body).not_to include("Visserie")

      get finance_expense_reports_path(kind: "expenses")
      expect(CGI.unescapeHTML(response.body)).to include("Note de frais")
    end

    it "offre les deux boutons de création" do
      get finance_expense_reports_path

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Note de frais", "Note de mission")
      expect(body).to include(new_finance_expense_report_path(kind: "mileage"))
    end
  end

  describe "le changement d'entité" do
    it "laisse la comptabilité rebasculer une note enregistrée, et le trace" do
      report = mission

      expect {
        patch finance_expense_report_path(report), params: {
          expense_report: { kind: "mileage", human_id: human.id, legal_entity_id: societe.id,
                            submitted_on: "2026-06-01" }
        }
      }.to change { report.reload.legal_entity_id }.from(entity.id).to(societe.id)

      derniere = report.versions.last
      expect(derniere.event).to eq("update")
      expect(derniere.object_changes).to include("legal_entity_id")
    end

    it "le refuse une fois la note en traitement — sa pièce existe" do
      report = mission
      ExpenseReports::Process.new(expense_report: report, processed_on: Date.new(2026, 6, 5)).run!

      patch finance_expense_report_path(report.reload), params: {
        expense_report: { kind: "mileage", human_id: human.id, legal_entity_id: societe.id,
                          submitted_on: "2026-06-01" }
      }

      expect(report.reload.legal_entity_id).to eq(entity.id)
    end
  end

  # La clé doit être SEMÉE et ÉDITABLE : un barème qui change chaque année et
  # qu'il faut redéployer pour corriger n'est pas un barème, c'est une constante.
  describe "le barème dans Paramètres > Tarifs" do
    it "est semé au bon montant, dans le groupe « Frais »" do
      Rates::SeedFromCatalog.new.run

      rate = Rate.find_by(key: Pricing::Catalog::MILEAGE_PER_KM_KEY)
      expect(rate).to be_present
      expect(rate.amount_cents).to eq(47)
      expect(rate.group).to eq("Frais")
    end

    it "est semé de façon idempotente" do
      Rates::SeedFromCatalog.new.run
      expect { Rates::SeedFromCatalog.new.run }
        .not_to change { Rate.where(key: Pricing::Catalog::MILEAGE_PER_KM_KEY).count }
    end

    it "s'affiche dans l'écran des tarifs" do
      Rates::SeedFromCatalog.new.run

      get rates_path

      body = CGI.unescapeHTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(body).to include("Frais")
      expect(body).to include("Note de mission — indemnité par kilomètre")
    end
  end

  describe "le cycle comptable" do
    it "est le même que pour une note de frais : référence NM, écriture, total" do
      report = mission

      ExpenseReports::Process.new(expense_report: report, processed_on: Date.new(2026, 6, 5)).run!

      report.reload
      expect(report.reference).to eq("NM-2026-001")
      expect(report.status).to eq("processing")
      expect(report.journal_entry).to be_present
      expect(report.total_cents).to eq(3_948)
    end
  end
end
