require "rails_helper"

# UN règlement = UN encaissement. Ce qui se démultiplie, c'est sa ventilation :
# un virement de 280 € qui paie 230 € de charges et 50 € de dôme reste un seul
# paiement, porté par deux écritures.
RSpec.describe Finance::RecordSettlement do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  describe "poste unique" do
    it "écrit une écriture négative et son règlement, sur le poste demandé" do
      settlement = described_class.new(member_account: account, amount_cents: 34_500,
                                       received_on: Date.new(2026, 8, 31), flow: "charges").run!

      expect(settlement.account_entries.sole.flow).to eq("charges")
      expect(settlement.account_entries.sole.amount_cents).to eq(-34_500)
      expect(settlement.account_entry).to eq(settlement.account_entries.sole)
      expect(account.reload.balance_cents).to eq(-34_500)
    end

    # Un règlement dont on ne sait pas ce qu'il paie ne doit pas être rangé au
    # hasard dans un poste : il tombe dans « Divers », où il se voit.
    it "tombe dans « Divers » sans poste" do
      settlement = described_class.new(member_account: account, amount_cents: 1_000,
                                       received_on: Date.new(2026, 8, 31)).run!

      expect(settlement.account_entries.sole.flow).to eq("other")
    end

    it "nomme le canal de réception dans le libellé quand il n'est pas la banque" do
      settlement = described_class.new(member_account: account, amount_cents: 2_000, method: "cash",
                                       received_on: Date.new(2026, 8, 31), received_channel: "bar_box").run!

      expect(settlement.account_entries.sole.label).to eq("Règlement — Espèces (Caisse du bar)")
    end
  end

  describe "ventilation sur plusieurs postes" do
    it "écrit une écriture par poste, sous un seul règlement" do
      settlement = described_class.new(member_account: account, amount_cents: 28_000,
                                       received_on: Date.new(2026, 6, 30),
                                       ventilation: { "charges" => 23_000, "dome" => 5_000 }).run!

      expect(settlement.account_entries.count).to eq(2)
      expect(settlement.account_entries.sum(:amount_cents)).to eq(-28_000)
      expect(settlement.account_entries.pluck(:flow)).to contain_exactly("charges", "dome")
      expect(account.reload.balance_cents).to eq(-28_000)
    end

    it "nomme le poste dans le libellé de chaque écriture" do
      settlement = described_class.new(member_account: account, amount_cents: 28_000,
                                       received_on: Date.new(2026, 6, 30),
                                       ventilation: { "charges" => 23_000, "dome" => 5_000 }).run!

      expect(settlement.account_entries.map(&:label))
        .to contain_exactly("Règlement — Virement — Charges", "Règlement — Virement — Dôme")
    end

    it "refuse une ventilation qui ne retombe pas sur le montant encaissé" do
      expect do
        described_class.new(member_account: account, amount_cents: 28_000,
                            received_on: Date.new(2026, 6, 30),
                            ventilation: { "charges" => 23_000 }).run!
      end.to raise_error(described_class::VentilationMismatch)

      expect(account.reload.account_entries).to be_empty
      expect(AccountSettlement.count).to eq(0)
    end

    it "suffixe chaque clé d'idempotence du poste, sinon la seconde écriture est refusée" do
      settlement = described_class.new(member_account: account, amount_cents: 28_000,
                                       received_on: Date.new(2026, 6, 30),
                                       idempotency_key: "settlement:cash_entry:7",
                                       ventilation: { "charges" => 23_000, "dome" => 5_000 }).run!

      expect(settlement.account_entries.pluck(:idempotency_key))
        .to contain_exactly("settlement:cash_entry:7:charges", "settlement:cash_entry:7:dome")
    end

    it "garde la clé telle quelle sur un règlement à poste unique" do
      settlement = described_class.new(member_account: account, amount_cents: 28_000,
                                       received_on: Date.new(2026, 6, 30), flow: "charges",
                                       idempotency_key: "settlement:cash_entry:7").run!

      expect(settlement.account_entries.sole.idempotency_key).to eq("settlement:cash_entry:7")
    end
  end
end
