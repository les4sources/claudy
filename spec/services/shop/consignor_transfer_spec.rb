require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 4 — à qui revient un virement « ARTISANAT <PRÉNOM> ».
RSpec.describe Shop::ConsignorTransfer do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:bank) { build_cash_account(entity, bank_account) }
  let!(:artisanat) { build_general_account(code: "701005", name: "Artisanat", klass: 7, nature: "revenue") }
  let!(:emilie) { Consignor.create!(name: "Émilie Dupont", settlement_mode: "invoice") }
  let!(:anne) { Consignor.create!(name: "Anne", settlement_mode: "invoice") }

  def entry_with(communication, amount_cents: 1_500, account: bank)
    build_cash_entry(account, amount_cents: amount_cents).tap { |e| e.update!(communication: communication) }
  end

  def transfer_for(entry) = described_class.new(cash_entry: entry)

  describe "#suggested_consignor" do
    it "reconnaît le mot-clé sans casse ni accents, au milieu de la communication" do
      expect(transfer_for(entry_with("Merci ! artisanat émilie")).suggested_consignor).to eq(emilie)
    end

    it "exige le mot entier : ARTISANAT ANNETTE n'est pas Anne" do
      expect(transfer_for(entry_with("ARTISANAT ANNETTE")).suggested_consignor).to be_nil
      expect(transfer_for(entry_with("ARTISANAT ANNE")).suggested_consignor).to eq(anne)
    end

    it "ne choisit pas entre deux homonymes actifs" do
      Consignor.create!(name: "Emilie Martin", settlement_mode: "invoice")

      expect(transfer_for(entry_with("ARTISANAT EMILIE")).suggested_consignor).to be_nil
    end

    it "préfère l'artisan actif à un homonyme parti" do
      Consignor.create!(name: "Emilie Martin", settlement_mode: "invoice", active: false)

      expect(transfer_for(entry_with("ARTISANAT EMILIE")).suggested_consignor).to eq(emilie)
    end

    it "sans mot-clé, personne" do
      expect(transfer_for(entry_with("EPICERIE")).suggested_consignor).to be_nil
    end
  end

  describe "#eligible?" do
    it "un encaissement bancaire, avec un compte artisanat au plan" do
      expect(transfer_for(entry_with("ARTISANAT EMILIE"))).to be_eligible
    end

    it "pas un décaissement" do
      expect(transfer_for(entry_with("ARTISANAT EMILIE", amount_cents: -1_500))).not_to be_eligible
    end

    it "pas une ligne de caisse : les espèces sont déclarées sur le relevé" do
      caisse = build_cash_account(entity, build_general_account(code: "570000", name: "Caisse"),
                                  name: "Caisse centrale", kind: "cash")

      expect(transfer_for(entry_with("ARTISANAT EMILIE", account: caisse))).not_to be_eligible
    end

    it "pas sans compte artisanat" do
      artisanat.update!(active: false)

      expect(transfer_for(entry_with("ARTISANAT EMILIE"))).not_to be_eligible
    end
  end

  describe "#link! et #unlink_if_orphan!" do
    it "rattache l'artisan, puis le détache quand l'affectation artisanat disparaît" do
      entry = entry_with("ARTISANAT EMILIE")
      allocation = allocate(entry, account: artisanat, amount_cents: 1_500, entity: entity)
      transfer_for(entry).link!(emilie)
      expect(entry.reload.consignor).to eq(emilie)

      allocation.destroy!
      transfer_for(entry.reload).unlink_if_orphan!

      expect(entry.reload.consignor).to be_nil
    end
  end
end
