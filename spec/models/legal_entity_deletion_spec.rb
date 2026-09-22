require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #355 — savoir CE QUI bloque la suppression d'une entité, sans affaiblir
# le garde qui la bloque. L'ergonomie du message ne doit rien contourner.
RSpec.describe LegalEntity, "la suppression et ce qui la bloque" do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Marco & Vespucci SRL", form: "srl") }

  it "se supprime quand elle ne porte rien" do
    expect(entity).to be_deletable
    expect(entity.destroy).to be_truthy
  end

  it "refuse toujours la suppression dès qu'elle porte quoi que ce soit" do
    build_fiscal_year(entity)

    expect(entity.destroy).to be_falsey
    expect(LegalEntity.find(entity.id)).to be_present
  end

  it "compte chaque cause séparément" do
    build_fiscal_year(entity)
    bank = build_general_account(code: "550000", name: "Triodos")
    revenue = build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue")
    build_cash_account(entity, bank)
    post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)

    expect(entity.deletion_blockers).to eq(fiscal_years: 1, cash_accounts: 1, journal_entries: 1)
  end

  it "ne retient que les causes présentes" do
    build_fiscal_year(entity)

    expect(entity.deletion_blockers).to eq(fiscal_years: 1)
  end

  describe "#blocked_only_by_empty_fiscal_years?" do
    it "est vrai pour une entité qui ne porte qu'un exercice vide et ouvert" do
      build_fiscal_year(entity)

      expect(entity).to be_blocked_only_by_empty_fiscal_years
      expect(entity.removable_fiscal_years.size).to eq(1)
    end

    it "est faux quand l'exercice est clôturé" do
      build_fiscal_year(entity, year: 2025).close!

      expect(entity).not_to be_blocked_only_by_empty_fiscal_years
      expect(entity.removable_fiscal_years).to be_empty
      expect(entity.closed_fiscal_years.size).to eq(1)
    end

    it "est faux quand l'entité porte une écriture" do
      build_fiscal_year(entity)
      bank = build_general_account(code: "550000", name: "Triodos")
      revenue = build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue")
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)

      expect(entity).not_to be_blocked_only_by_empty_fiscal_years
    end

    it "est faux quand l'entité porte un compte de trésorerie" do
      build_fiscal_year(entity)
      build_cash_account(entity, build_general_account(code: "550000", name: "Triodos"))

      expect(entity).not_to be_blocked_only_by_empty_fiscal_years
    end

    it "est faux pour une entité qui ne bloque sur rien" do
      expect(entity).not_to be_blocked_only_by_empty_fiscal_years
    end
  end
end
