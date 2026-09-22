require "rails_helper"
require Rails.root.join("db/migrate/20260922040000_seed_shop_revenue_accounts.rb")

# Epic #359, phase 1 — les comptes de produit des trois carnets.
#
# La migration tourne sur une base où `701002` et compagnie existent déjà en
# production : elle doit donc être exécutable deux fois sans rien casser ni rien
# renommer.
RSpec.describe SeedShopRevenueAccounts do
  let(:entity) do
    LegalEntity.create!(name: "Fondation Les 4 Sources", form: "foundation", vat_regime: "exempt")
  end

  def run! = described_class.new.up

  it "crée les trois comptes de produit s'ils manquent" do
    run!

    expect(GeneralAccount.find_by(code: "701005")).to have_attributes(
      name: "Artisanat (dépôt-vente)", klass: 7, nature: "revenue"
    )
    expect(GeneralAccount.where(code: %w[701002 701003 701005]).count).to eq(3)
  end

  it "ne renomme jamais un compte déjà là" do
    GeneralAccount.create!(code: "701002", name: "Cellier / épicerie", klass: 7, nature: "revenue")

    run!

    expect(GeneralAccount.find_by(code: "701002").name).to eq("Cellier / épicerie")
  end

  it "repointe le motif « Épicerie » sur le compte du cellier" do
    fourre_tout = GeneralAccount.create!(code: "700300", name: "Bar et cellier", klass: 7, nature: "revenue")
    motif = CashMotif.create!(label: "Épicerie", direction: "in",
                              general_account: fourre_tout, legal_entity: entity)

    run!

    expect(motif.reload.general_account.code).to eq("701002")
  end

  it "laisse les autres motifs où ils sont" do
    fourre_tout = GeneralAccount.create!(code: "700300", name: "Bar et cellier", klass: 7, nature: "revenue")
    bar = CashMotif.create!(label: "Bar", direction: "in",
                            general_account: fourre_tout, legal_entity: entity)

    run!

    expect(bar.reload.general_account.code).to eq("700300")
  end

  it "se relance sans créer de doublon" do
    run!

    expect { run! }.not_to(change { GeneralAccount.count })
  end
end
