require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 2 — Comptabilité > Stripe.
#
# Le mode d'un compte se changeait en console, les correspondances par catégorie
# se créaient au rake : une décision de gestion derrière un accès SSH.
RSpec.describe "Comptabilité > Stripe", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-stripe@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:stripe_compte) { build_general_account(code: "551000", name: "Stripe") }
  let!(:ventes) { build_general_account(code: "700100", name: "Ventes épicerie", klass: 7, nature: "revenue") }
  let!(:epicerie) { Team.create!(name: "Pôle Épicerie", kind: "economic") }

  let!(:compte) do
    CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                        general_account: stripe_compte, stripe_account_key: "tranche_de_vie",
                        stripe_mode: "ledger")
  end

  before { sign_in user }

  def transaction(category:, gross_cents: 1_000, stripe_id: SecureRandom.hex(4))
    StripeBalanceTransaction.create!(account_key: "tranche_de_vie", cash_account: compte,
                                     stripe_id: stripe_id, kind: "charge", category: category,
                                     gross_cents: gross_cents, fee_cents: 30,
                                     net_cents: gross_cents - 30, occurred_at: Time.current)
  end

  describe "l'écran" do
    it "montre chaque compte Stripe, son mode et ses compteurs" do
      transaction(category: "pain")

      get finance_stripe_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stripe Tranches de Vie")
      expect(response.body).to include("Grand livre")
      expect(response.body).to include("subnav-accounting")
    end

    it "liste les correspondances existantes" do
      StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                    general_account: ventes, team: epicerie)

      get finance_stripe_path

      expect(response.body).to include("pain", "700100", "Pôle Épicerie")
    end

    # C'est CE bloc qui explique pourquoi des lignes restent en attente.
    it "signale les catégories rencontrées qu'aucune correspondance ne couvre" do
      transaction(category: "légumes")

      get finance_stripe_path

      expect(response.body).to include("sans correspondance")
      expect(response.body).to include("légumes")
      expect(response.body).to include("Créer la correspondance")
    end

    # « Sans catégorie » est une catégorie, pas une absence à ignorer.
    it "compte « sans catégorie » parmi les catégories à couvrir" do
      transaction(category: nil)

      get finance_stripe_path

      expect(response.body).to include(StripeCategoryMapping::NO_CATEGORY_LABEL)
    end

    it "ne signale plus une catégorie une fois couverte" do
      transaction(category: "pain")
      StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain", general_account: ventes)

      get finance_stripe_path

      expect(response.body).not_to include("sans correspondance")
    end
  end

  describe "le changement de mode" do
    it "passe un compte en mode par versement quand rien n'a été importé" do
      patch finance_stripe_account_mode_path(compte, stripe_mode: "per_payout")

      expect(compte.reload.stripe_mode).to eq("per_payout")
      expect(flash[:notice]).to include("Par versement")
    end

    # Les lignes déjà entrées au journal deviendraient orphelines de leur mode.
    it "refuse de revenir en arrière quand des transactions grand livre existent" do
      transaction(category: "pain")

      patch finance_stripe_account_mode_path(compte, stripe_mode: "per_payout")

      expect(compte.reload.stripe_mode).to eq("ledger")
      expect(flash[:alert]).to include("mode grand livre")
    end

    it "refuse un mode inconnu" do
      patch finance_stripe_account_mode_path(compte, stripe_mode: "nimporte_quoi")

      expect(compte.reload.stripe_mode).to eq("ledger")
      expect(flash[:alert]).to include("Mode inconnu")
    end
  end

  describe "les correspondances" do
    it "préremplit le formulaire depuis une catégorie non couverte" do
      get new_finance_stripe_category_mapping_path(account_key: "tranche_de_vie", category: "légumes")

      expect(response.body).to include("légumes")
      expect(response.body).to include("tranche_de_vie")
    end

    it "crée une correspondance" do
      expect {
        post finance_stripe_category_mappings_path,
             params: { stripe_category_mapping: { account_key: "tranche_de_vie", category: "pain",
                                                  general_account_id: ventes.id, team_id: epicerie.id } }
      }.to change(StripeCategoryMapping, :count).by(1)

      expect(response).to redirect_to(finance_stripe_path)
      expect(StripeCategoryMapping.order(:id).last.team).to eq(epicerie)
    end

    it "crée la correspondance « sans catégorie » quand le champ est vide" do
      post finance_stripe_category_mappings_path,
           params: { stripe_category_mapping: { account_key: "tranche_de_vie", category: "",
                                                general_account_id: ventes.id } }

      expect(StripeCategoryMapping.order(:id).last.category).to be_nil
    end

    it "refuse un doublon de catégorie sur le même compte" do
      StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain", general_account: ventes)

      expect {
        post finance_stripe_category_mappings_path,
             params: { stripe_category_mapping: { account_key: "tranche_de_vie", category: "pain",
                                                  general_account_id: ventes.id } }
      }.not_to change(StripeCategoryMapping, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "met à jour une correspondance" do
      mapping = StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                              general_account: ventes)

      patch finance_stripe_category_mapping_path(mapping),
            params: { stripe_category_mapping: { account_key: "tranche_de_vie", category: "pain",
                                                 general_account_id: ventes.id, team_id: epicerie.id } }

      expect(mapping.reload.team).to eq(epicerie)
    end

    # Les lignes déjà affectées portent une COPIE de ses attributs : retirer la
    # correspondance ne doit pas les rendre illisibles.
    it "retire une correspondance en douceur, sans la détruire" do
      mapping = StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                              general_account: ventes)

      delete finance_stripe_category_mapping_path(mapping)

      expect(StripeCategoryMapping.where(id: mapping.id)).to be_empty
      StripeCategoryMapping.with_deleted do
        expect(StripeCategoryMapping.unscoped.where(id: mapping.id)).to be_present
      end
    end
  end
end
