require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Rentrer une note de frais reste l'affaire de chaque membre (Michael,
# 2026-11-12) : la Comptabilité est réservée aux Administratifs, mais un
# Sourcier saisit sa note depuis son tableau de bord. Le traitement, la liste
# et la fiche restent en Comptabilité.
RSpec.describe "Note de frais saisie par un Sourcier", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "membre@les4sources.be", password: "password123", access_roles: %w[sourcier]) }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let(:human) { Human.create!(name: "Sébastien Test", iban: "BE68539007547034") }

  before { sign_in user }

  it "ouvre le formulaire et ramène au tableau de bord après l'enregistrement" do
    get new_finance_expense_report_path(kind: "expenses", human_id: human.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(href="#{dashboard_path}"))

    expect {
      post finance_expense_reports_path, params: {
        expense_report: {
          human_id: human.id, legal_entity_id: entity.id, kind: "expenses", submitted_on: Date.current.to_s,
          expense_lines_attributes: { "0" => { spent_on: Date.current.to_s, label: "Visserie",
                                               amount_in_euros: "24,90", receipt_on_paper: "1" } }
        }
      }
    }.to change(ExpenseReport, :count).by(1)

    expect(response).to redirect_to(dashboard_path(human_id: human.id))
  end

  it "garde la liste et la fiche en Comptabilité" do
    get finance_expense_reports_path
    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to eq(AccessControl::NO_ACCESS)
  end

  it "propose le bouton sur le tableau de bord" do
    get dashboard_path
    expect(response.body).to include(new_finance_expense_report_path(kind: "expenses"))
  end
end
