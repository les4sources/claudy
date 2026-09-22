require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #355 — le refus de supprimer une entité conseillait la désactivation
# même quand un simple exercice vide bloquait, alors que le supprimer suffisait.
RSpec.describe "Comptabilité > Entités", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }

  before { sign_in user }

  describe "DELETE /finance/entities/:id" do
    it "supprime une entité qui ne porte rien" do
      entity = build_legal_entity(name: "Entité vide")

      delete finance_legal_entity_path(entity)

      expect(flash[:notice]).to eq("Entité supprimée.")
      expect(LegalEntity.where(id: entity.id)).to be_empty
    end

    # Le cas de Marco & Vespucci SRL en production : un exercice 2026 vide,
    # aucun compte, aucune écriture. La désactivation était le mauvais conseil.
    it "nomme l'exercice vide et mène à la page des exercices" do
      entity = build_legal_entity(name: "Marco & Vespucci SRL", form: "srl")
      build_fiscal_year(entity)

      delete finance_legal_entity_path(entity)

      expect(flash[:alert]).to include("1 exercice")
      expect(flash[:alert]).to include(finance_fiscal_years_path(legal_entity_id: entity.id))
      expect(flash[:alert]).not_to include("désactive-la")
      expect(LegalEntity.find(entity.id)).to be_present
    end

    it "conseille la désactivation quand l'entité porte une vraie comptabilité" do
      entity = build_legal_entity(name: "Fondation Les 4 Sources")
      build_fiscal_year(entity)
      bank = build_general_account(code: "550000", name: "Triodos")
      revenue = build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue")
      build_cash_account(entity, bank)
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)

      delete finance_legal_entity_path(entity)

      expect(flash[:alert]).to include("désactive-la")
      expect(flash[:alert]).to include("1 écriture", "1 compte de trésorerie")
      expect(flash[:alert]).not_to include(finance_fiscal_years_path(legal_entity_id: entity.id))
    end

    it "dit qu'un exercice clôturé ne se supprime pas" do
      entity = build_legal_entity(name: "Domaine d'Ahinvaux")
      build_fiscal_year(entity, year: 2025).close!

      delete finance_legal_entity_path(entity)

      expect(flash[:alert]).to include("clôturé")
      expect(flash[:alert]).to include("désactive-la")
      expect(flash[:alert]).not_to include(finance_fiscal_years_path(legal_entity_id: entity.id))
    end
  end

  describe "GET /finance/entities" do
    it "affiche ce que chaque entité porte, y compris zéro" do
      empty = build_legal_entity(name: "Entité vide")
      loaded = build_legal_entity(name: "Entité chargée")
      build_fiscal_year(loaded)
      bank = build_general_account(code: "550000", name: "Triodos")
      revenue = build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue")
      build_cash_account(loaded, bank)
      post_simple_entry(entity: loaded, debit_account: bank, credit_account: revenue)

      get finance_legal_entities_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Exercices", "Écritures")
      # Les compteurs de l'entité chargée : 1 exercice, 1 compte, 1 écriture ;
      # ceux de l'entité vide : trois zéros.
      expect(response.body).to include(finance_fiscal_years_path(legal_entity_id: loaded.id))
      expect(response.body).to include(finance_fiscal_years_path(legal_entity_id: empty.id))
      expect(counters_for(response.body, "Entité chargée")).to eq(["1", "1", "1"])
      expect(counters_for(response.body, "Entité vide")).to eq(["0", "0", "0"])
    end
  end

  # Les trois cellules chiffrées de la ligne d'une entité, dans l'ordre du
  # tableau : exercices, comptes de trésorerie, écritures.
  def counters_for(body, name)
    row = body[body.index(name)..].split("</tr>").first
    row.scan(%r{text-right"[^>]*>\s*(?:<a[^>]*>)?\s*(\d+)}).flatten
  end
end
