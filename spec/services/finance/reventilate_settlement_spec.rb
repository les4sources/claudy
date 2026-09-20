require "rails_helper"

# Redécouper un encaissement déjà encodé sans jamais en changer le montant.
# C'est LA garantie du service : un outil de correction qui peut bouger un
# solde est un outil qui finira par le bouger.
RSpec.describe Finance::ReventilateSettlement do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  # Le virement mensuel de Seb : 280 € encodés entièrement sur les charges,
  # alors qu'ils payaient 230 € de charges et 50 € de dôme.
  let(:settlement) do
    Finance::RecordSettlement.new(member_account: account, amount_cents: 28_000,
                                  received_on: Date.new(2026, 6, 30), flow: "charges",
                                  reference: "participation famille").run!
  end

  def soldes_par_poste
    account.reload.account_entries.group(:flow).sum(:amount_cents)
  end

  it "redécoupe l'encaissement sans toucher au solde" do
    settlement
    avant = account.reload.balance_cents

    described_class.new(settlement: settlement,
                        ventilation: { "charges" => 23_000, "dome" => 5_000 }).run!

    expect(account.reload.balance_cents).to eq(avant)
    expect(soldes_par_poste).to eq({ "charges" => -23_000, "dome" => -5_000 })
  end

  it "rattache toutes les écritures au même règlement" do
    settlement

    described_class.new(settlement: settlement,
                        ventilation: { "charges" => 23_000, "dome" => 5_000 }).run!

    expect(settlement.reload.account_entries.count).to eq(2)
    expect(settlement.account_entry).to be_present
    expect(settlement.account_entries.sum(:amount_cents)).to eq(-28_000)
  end

  it "nomme le poste dans le libellé quand il y en a plusieurs" do
    settlement

    described_class.new(settlement: settlement,
                        ventilation: { "charges" => 23_000, "dome" => 5_000 }).run!

    expect(settlement.reload.account_entries.map(&:label))
      .to contain_exactly("Règlement — Virement — Charges", "Règlement — Virement — Dôme")
  end

  it "refuse une ventilation qui ne retombe pas sur le montant" do
    settlement

    expect { described_class.new(settlement: settlement, ventilation: { "charges" => 20_000 }).run! }
      .to raise_error(described_class::Mismatch, /200 €.+280 €/)
    expect(soldes_par_poste).to eq({ "charges" => -28_000 })
  end

  it "refuse de toucher à une écriture rattachée à un décompte émis" do
    settlement
    settlement.account_entry.update_column(:locked_at, Time.current)

    expect { described_class.new(settlement: settlement, ventilation: { "charges" => 23_000, "dome" => 5_000 }).run! }
      .to raise_error(described_class::Locked)
  end

  # Rejouer la ventilation sur un règlement déjà ventilé doit repartir de ses
  # écritures actuelles, sans jamais dupliquer le montant.
  it "se rejoue sur un règlement déjà ventilé" do
    settlement
    described_class.new(settlement: settlement, ventilation: { "charges" => 23_000, "dome" => 5_000 }).run!
    avant = account.reload.balance_cents

    described_class.new(settlement: settlement.reload, ventilation: { "charges" => 28_000 }).run!

    expect(account.reload.balance_cents).to eq(avant)
    expect(soldes_par_poste).to eq({ "charges" => -28_000 })
    expect(settlement.reload.account_entries.count).to eq(1)
  end
end
