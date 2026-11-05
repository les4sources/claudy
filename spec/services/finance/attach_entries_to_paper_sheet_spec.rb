require "rails_helper"

# Feuille de bar d'octobre 2026 : 45 écritures posées une par une par le
# connecteur, sans fiche. Le rattachement doit les montrer sur la fiche du mois
# sans jamais les refacturer.
RSpec.describe Finance::AttachEntriesToPaperSheet do
  let(:month) { Date.new(2026, 10, 1) }
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:ada) { MemberAccount.create!(kind: "household", household: household, name: "Ada") }
  let(:bob) { MemberAccount.create!(kind: "entity", name: "Semisto") }

  let!(:moinette) do
    item = CatalogItem.create!(name: "Moinette", channel: "bar", unit: "piece")
    item.catalog_prices.create!(active_from: Date.new(2023, 1, 1), member_price_cents: 201)
    item
  end

  let!(:kefir) do
    item = CatalogItem.create!(name: "Kéfir (Eau Vertueuse)", channel: "bar", unit: "piece")
    item.catalog_prices.create!(active_from: Date.new(2023, 1, 1), member_price_cents: 160)
    item
  end

  def bar_entry(account, label, cents, **attrs)
    AccountEntry.create!(member_account: account, entry_date: Date.new(2026, 10, 31), amount_cents: cents,
                         flow: "bar", kind: "bar", source: "claude", label: label,
                         idempotency_key: "claude-ecriture:#{SecureRandom.hex(6)}", **attrs)
  end

  def run(apply: false) = described_class.new(month: month, channel: "bar", apply: apply).run

  it "à blanc, ne crée ni fiche ni rattachement" do
    entry = bar_entry(ada, "Moinette", 804)

    report = run

    expect(report.attached.map(&:entry)).to eq([entry])
    expect(PaperSheet.count).to eq(0)
    expect(entry.reload.paper_sheet_id).to be_nil
  end

  it "crée la fiche du mois et y rattache les écritures, sans toucher aux montants" do
    entry = bar_entry(ada, "Moinette", 804)
    other = bar_entry(bob, "kefir (eau vertueuse)", 450)

    report = run(apply: true)

    sheet = report.sheet.reload
    expect(sheet.period_month).to eq(month)
    expect(sheet.status).to eq("encoded")
    expect(sheet.account_entries).to contain_exactly(entry, other)
    expect(sheet.total_cents).to eq(1254)

    entry.reload
    expect(entry.amount_cents).to eq(804)
    expect(entry.catalog_item_id).to eq(moinette.id)
    expect(entry.quantity).to eq(4)
    expect(entry.unit_price_cents).to eq(201)
    expect(entry.idempotency_key).to eq("sheet:#{sheet.id}:#{ada.id}:#{moinette.id}")
  end

  it "rattache aussi une écriture verrouillée par un décompte émis, qui reste verrouillée" do
    entry = bar_entry(ada, "Moinette", 402, locked_at: Time.current)

    run(apply: true)

    expect(entry.reload.paper_sheet_id).to be_present
    expect(entry).to be_locked
    expect(entry.amount_cents).to eq(402)
  end

  it "laisse la quantité vide quand le montant n'est pas un multiple du prix, et passe la fiche en montants" do
    entry = bar_entry(bob, "Kéfir (Eau Vertueuse)", 450)

    report = run(apply: true)

    expect(entry.reload.quantity).to be_nil
    expect(report.sheet.reload.entry_mode).to eq("amount")
  end

  it "laisse de côté un libellé sans article et un doublon de cellule" do
    bar_entry(ada, "Moinette", 201)
    doublon = bar_entry(ada, "Moinette", 402)
    inconnu = bar_entry(ada, "Anières", 300)

    report = run(apply: true)

    expect(report.unmatched.map(&:entry)).to eq([inconnu])
    expect(report.conflicts.map(&:entry)).to eq([doublon])
    expect(inconnu.reload.paper_sheet_id).to be_nil
    expect(doublon.reload.paper_sheet_id).to be_nil
  end

  it "ignore les règlements, les autres postes et les autres mois" do
    bar_entry(ada, "Moinette", -500, kind: "settlement")
    AccountEntry.create!(member_account: ada, entry_date: Date.new(2026, 10, 31), amount_cents: 500,
                         flow: "grocery", kind: "grocery", label: "Moinette")
    AccountEntry.create!(member_account: ada, entry_date: Date.new(2026, 11, 30), amount_cents: 201,
                         flow: "bar", kind: "bar", label: "Moinette")

    expect(run.attached).to be_empty
  end

  it "réenregistrer la fiche ensuite ne refacture rien" do
    entry = bar_entry(ada, "Moinette", 804)
    sheet = run(apply: true).sheet

    expect do
      Finance::EncodePaperSheet.new(sheet: sheet.reload, cells: { ada.id => { moinette.id => "4" } }).run!
    end.not_to change(AccountEntry, :count)
    expect(entry.reload.amount_cents).to eq(804)
  end

  it "est rejouable : une écriture rattachée n'est plus candidate" do
    bar_entry(ada, "Moinette", 804)
    run(apply: true)

    expect(run(apply: true).attached).to be_empty
    expect(PaperSheet.count).to eq(1)
  end
end
