require "rails_helper"

# Issue #159 — écrans Finances > Charges récurrentes.
RSpec.describe "Finances > Charges récurrentes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:household) { Household.create!(name: "Famille Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Famille Chevêche") }

  before { sign_in user }

  describe "CRUD" do
    it "crée une charge à montant fixe" do
      expect {
        post finance_recurring_charges_path, params: {
          recurring_charge: { member_account_id: account.id, label: "Forfait dôme", basis: "flat",
                              flow: "dome", starts_on: "2023-01-01" },
          amount_euros: nil
        }.deep_merge(recurring_charge: { amount_euros: "50" })
      }.to change(RecurringCharge, :count).by(1)

      expect(RecurringCharge.last.amount_cents).to eq(5000)
    end

    it "refuse une charge qui porte à la fois un montant et une clé" do
      expect {
        post finance_recurring_charges_path, params: {
          recurring_charge: { member_account_id: account.id, label: "Ambiguë", basis: "flat",
                              rate_key: "dome.monthly_flat", amount_euros: "50", starts_on: "2023-01-01" }
        }
      }.not_to change(RecurringCharge, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuse une charge sans montant ni clé" do
      expect {
        post finance_recurring_charges_path, params: {
          recurring_charge: { member_account_id: account.id, label: "Vide", basis: "flat", starts_on: "2023-01-01" }
        }
      }.not_to change(RecurringCharge, :count)
    end
  end

  describe "aperçu et génération" do
    before do
      RecurringCharge.create!(member_account: account, label: "Forfait dôme", basis: "flat",
                              amount_cents: 5000, flow: "dome", starts_on: Date.new(2023, 1, 1))
    end

    # L'aperçu doit être un vrai dry-run : il montre sans écrire.
    it "l'aperçu n'écrit rien" do
      expect {
        get preview_finance_recurring_charges_path(month: "2026-08")
      }.not_to change(AccountEntry, :count)

      expect(response.body).to include("Forfait dôme")
      expect(response.body).to include("50,00")
    end

    it "la confirmation écrit" do
      expect {
        post generate_finance_recurring_charges_path(month: "2026-08")
      }.to change(AccountEntry, :count).by(1)

      expect(response).to redirect_to(finance_recurring_charges_path(month: "2026-08"))
    end

    it "la seconde confirmation ne duplique rien" do
      post generate_finance_recurring_charges_path(month: "2026-08")

      expect {
        post generate_finance_recurring_charges_path(month: "2026-08")
      }.not_to change(AccountEntry, :count)
    end

    it "signale dans l'aperçu ce qui est déjà généré" do
      post generate_finance_recurring_charges_path(month: "2026-08")

      get preview_finance_recurring_charges_path(month: "2026-08")

      expect(response.body).to include("Déjà générées")
    end
  end

  describe "sans authentification" do
    it "redirige vers la connexion" do
      sign_out user

      get finance_recurring_charges_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
