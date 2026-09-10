require "rails_helper"
require Rails.root.join("spec/support/revenue_share_builders")
require Rails.root.join("spec/support/finance_builders")

# Issue #247 — Comptabilité > Partages de revenus, de bout en bout.
RSpec.describe "Comptabilité > Partages de revenus", type: :request do
  include Devise::Test::IntegrationHelpers
  include RevenueShareBuilders
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:lodging) { build_tiny_house }

  before { sign_in user }

  def base_params(overrides = {})
    { revenue_share_agreement: { lodging_id: lodging.id, beneficiary_name: "Famille Dubois",
                                 beneficiary_email: "dubois@example.com",
                                 beneficiary_iban: "BE68539007547034", share_percent: 50,
                                 period: "quarterly", starts_on: "2026-01-01",
                                 active: "1" }.merge(overrides) }
  end

  describe "GET /finance/revenue_shares" do
    it "liste les accords et vit dans la sous-navigation Comptabilité" do
      build_agreement(lodging)

      get finance_revenue_share_agreements_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Famille Dubois", "Tiny house", "50 %", "Trimestrielle")
      expect(response.body).to include("subnav-accounting")
    end

    it "n'affiche jamais l'IBAN en entier" do
      build_agreement(lodging)

      get finance_revenue_share_agreements_path

      expect(response.body).not_to include("BE68539007547034")
      expect(response.body).to include("7034")
    end

    it "le dit quand aucun accord n'existe" do
      get finance_revenue_share_agreements_path
      expect(response.body).to include("Aucun accord de partage")
    end
  end

  describe "POST /finance/revenue_shares" do
    it "crée l'accord" do
      expect { post finance_revenue_share_agreements_path, params: base_params }
        .to change(RevenueShareAgreement, :count).by(1)

      expect(response).to redirect_to(finance_revenue_share_agreement_path(RevenueShareAgreement.last))
    end

    it "refuse un IBAN invalide et réaffiche le formulaire" do
      post finance_revenue_share_agreements_path, params: base_params(beneficiary_iban: "NIMPORTEQUOI")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(RevenueShareAgreement.count).to eq(0)
    end
  end

  describe "PATCH deactivate / reactivate" do
    it "désactive puis réactive sans rien supprimer" do
      accord = build_agreement(lodging)

      patch deactivate_finance_revenue_share_agreement_path(accord)
      expect(accord.reload.active).to be(false)

      patch reactivate_finance_revenue_share_agreement_path(accord)
      expect(accord.reload.active).to be(true)
    end
  end

  describe "la génération d'un relevé" do
    let(:accord) { build_agreement(lodging) }

    it "génère le brouillon de la période et montre les écartées avec leur raison" do
      build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
      build_tiny_booking(lodging, from: Date.new(2026, 2, 3), price_cents: 20_000, status: "canceled")

      post finance_revenue_share_agreement_statements_path(accord, period_from: "2026-01-01")

      statement = RevenueShareStatement.last
      expect(response).to redirect_to(finance_revenue_share_statement_path(statement))
      expect(statement.base_cents).to eq(30_000)
      expect(statement.share_cents).to eq(15_000)

      get finance_revenue_share_statement_path(statement)
      expect(response.body).to include("Écartées, et pourquoi", "annulée")
    end

    it "refuse une seconde génération sur la même période" do
      build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
      post finance_revenue_share_agreement_statements_path(accord, period_from: "2026-01-01")

      expect { post finance_revenue_share_agreement_statements_path(accord, period_from: "2026-01-01") }
        .not_to change(RevenueShareStatement, :count)
      expect(response).to redirect_to(finance_revenue_share_agreement_path(accord))
    end

    it "supprime un brouillon, jamais un relevé émis" do
      build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
      post finance_revenue_share_agreement_statements_path(accord, period_from: "2026-01-01")
      statement = RevenueShareStatement.last

      expect { delete finance_revenue_share_statement_path(statement) }
        .to change(RevenueShareStatement, :count).by(-1)
    end
  end

  describe "l'émission et le paiement" do
    let(:accord) { build_agreement(lodging) }
    let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
    let!(:fiscal_year) { build_fiscal_year(entity) }
    let!(:charge) do
      build_general_account(code: GeneralAccount::REVENUE_SHARE_CODE, name: "Reversements",
                            klass: 6, nature: "expense")
    end
    let!(:supplier) do
      build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability")
    end

    let(:statement) do
      build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 50_000)
      RevenueShares::Generate.new(agreement: accord, period_from: Date.new(2026, 1, 1)).run!
    end

    it "émet, puis laisse constater le paiement" do
      post issue_finance_revenue_share_statement_path(statement)
      expect(statement.reload.status).to eq("issued")

      patch mark_paid_finance_revenue_share_statement_path(statement), params: { paid_on: "2026-04-15" }
      expect(statement.reload.status).to eq("paid")
      expect(statement.paid_on).to eq(Date.new(2026, 4, 15))
    end

    it "refuse de marquer payé un brouillon" do
      patch mark_paid_finance_revenue_share_statement_path(statement)
      expect(statement.reload.status).to eq("draft")
    end
  end

  describe "la page publique à jeton" do
    let(:accord) { build_agreement(lodging) }

    let(:statement) do
      build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 50_000)
      RevenueShares::Generate.new(agreement: accord, period_from: Date.new(2026, 1, 1)).run!
    end

    it "s'ouvre sans session et porte la période, la base et la part" do
      sign_out user

      get public_revenue_share_statement_path(statement.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("T1 2026", "Tiny house", "500,00", "250,00")
      expect(response.body).to include(statement.reference)
    end

    it "renvoie 404 sur un jeton inconnu" do
      get public_revenue_share_statement_path("nimportequoi")
      expect(response).to have_http_status(:not_found)
    end
  end
end
