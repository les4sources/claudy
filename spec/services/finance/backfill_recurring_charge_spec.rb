require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La pension de Balthazar (2026-10-19) : une charge posée après coup, dont
# l'historique est payé depuis longtemps.
RSpec.describe Finance::BackfillRecurringCharge do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4) }
  let!(:produit) { build_general_account(code: "702001", name: "Balthazar", klass: 7, nature: "revenue") }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let!(:bene) { Human.create!(name: "Bénédicte Lambert", email: "bene@les4sources.be") }
  let!(:compte) { MemberAccount.for_human!(bene) }
  let!(:charge) do
    RecurringCharge.create!(member_account: compte, label: "Pension pour Balthazar", basis: "flat",
                            amount_cents: 3_000, flow: "pet", starts_on: Date.new(2025, 11, 1))
  end

  def virement(cents, date, communication: "Pension Balthazar")
    entry = build_cash_entry(compte_bancaire, amount_cents: cents, entry_date: date, label: "Virement Béné")
    entry.update!(communication: communication)
    entry
  end

  # Passé en produit lors de la reprise : affecté, la compta générale est juste.
  def deja_comptabilise(entry)
    allocate(entry, account: produit, amount_cents: entry.amount_cents, entity: entity)
    entry
  end

  let!(:nov_dec) { deja_comptabilise(virement(6_000, Date.new(2025, 12, 16), communication: "Balthazar nov-dec")) }
  let!(:janvier) { virement(3_000, Date.new(2026, 1, 5)) }
  let!(:bizarre) { virement(2_500, Date.new(2026, 1, 20)) }

  def run(apply:)
    described_class.new(charge: charge, cash_entries: CashEntry.where(id: [nov_dec, janvier, bizarre]),
                        through: Date.new(2026, 2, 1), apply: apply).run!
  end

  it "n'écrit rien sans APPLY" do
    report = nil
    expect { report = run(apply: false) }.not_to change(AccountEntry, :count)

    expect(report.charges.size).to eq(4)
    expect(report.settlements.map { |s| s[:month] }).to eq([Date.new(2025, 11, 1), Date.new(2025, 12, 1)])
    expect(report.links.map { |l| l[:entry] }).to eq([janvier])
    expect(janvier.reload.cash_allocations).to be_empty
  end

  describe "avec APPLY" do
    before { run(apply: true) }

    it "pose une charge par mois, sous la clé du générateur" do
      cles = compte.account_entries.where(flow: "pet", kind: "recurring").pluck(:idempotency_key)
      expect(cles).to match_array(%w[2025-11 2025-12 2026-01 2026-02].map { |m| "recurring:#{charge.id}:#{m}" })
    end

    it "règle les mois payés par un virement déjà comptabilisé, sans toucher la ligne" do
      refs = compte.account_settlements.where(received_on: nov_dec.entry_date).pluck(:reference)
      expect(refs).to match_array(%w[reprise-pet:2025-11 reprise-pet:2025-12])
      expect(nov_dec.reload.cash_allocations.map(&:general_account)).to eq([produit])
    end

    it "rapproche le virement encore à affecter : règlement et 400000" do
      allocation = janvier.reload.cash_allocations.sole
      expect(allocation.general_account).to eq(clients)
      expect(allocation.document).to eq(compte)
    end

    it "laisse dû le seul mois sans paiement" do
      poste = MemberAccounts::Outstanding.new(compte).postes.find { |p| p.flow == "pet" }
      expect(poste.amount_cents).to eq(3_000)
      expect(poste.lignes.map(&:entry_date)).to eq([Date.new(2026, 2, 28)])
    end

    it "ne refait rien au second passage" do
      expect { run(apply: true) }.not_to change(AccountEntry, :count)
    end
  end

  it "laisse de côté ce qui n'est pas un multiple du montant mensuel, et le dit" do
    report = run(apply: false)

    expect(report.skipped.map { |s| s[:entry] }).to eq([bizarre])
    expect(report.billed_unpaid).to eq([Date.new(2026, 2, 1)])
  end

  it "signale un mois payé avant le début de la règle" do
    charge.update!(starts_on: Date.new(2025, 12, 1))

    expect(run(apply: false).paid_unbilled).to eq([Date.new(2025, 11, 1)])
  end
end
