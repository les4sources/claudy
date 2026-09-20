require "rails_helper"

# Le poste d'un règlement historique se LIT, il ne se devine pas : un règlement
# rangé au mauvais endroit crée une dette imaginaire d'un côté et une avance
# imaginaire de l'autre, ce qui est pire que pas de poste du tout.
RSpec.describe Finance::BackfillSettlementFlows do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  def reglement(reference:, notes: nil, cents: 10_000)
    entry = account.account_entries.create!(entry_date: Date.new(2026, 6, 30), amount_cents: -cents,
                                            kind: "settlement", flow: "other", label: "Règlement")
    AccountSettlement.create!(member_account: account, account_entry: entry, amount_cents: cents,
                              received_on: Date.new(2026, 6, 30), reference: reference, notes: notes)
    entry
  end

  it "lit le poste dans la référence de la reprise" do
    bar = reglement(reference: "reprise-bar:2026-05")
    repas = reglement(reference: "reprise-restauration:2026-06-17:L35:Frennet")
    charges = reglement(reference: "reprise-charges:2025-12")
    loyer = reglement(reference: "banque-2026:Béné:06:loyer")

    described_class.new(dry_run: false).run!

    expect(bar.reload.flow).to eq("bar")
    expect(repas.reload.flow).to eq("meal")
    expect(charges.reload.flow).to eq("charges")
    expect(loyer.reload.flow).to eq("charges")
  end

  it "retombe sur le motif des notes quand la référence ne dit rien" do
    poulets = reglement(reference: "triodos-2026:SRC-0001:2026-02-04:25", notes: "Vente de poulets — rattrapage")
    frais = reglement(reference: "triodos-2026:SRC-0005:2026-02-10:10", notes: "Solde frais février 2026")

    described_class.new(dry_run: false).run!

    expect(poulets.reload.flow).to eq("grocery")
    expect(frais.reload.flow).to eq("charges")
  end

  it "laisse « Divers » et signale ce qui ne se lit pas" do
    muet = reglement(reference: "une-référence-qui-ne-dit-rien", notes: nil)

    rapport = described_class.new(dry_run: false).run!

    expect(muet.reload.flow).to eq("other")
    expect(rapport.skipped.size).to eq(1)
  end

  it "n'écrit rien en dry-run" do
    bar = reglement(reference: "reprise-bar:2026-05")

    rapport = described_class.new.run!

    expect(bar.reload.flow).to eq("other")
    expect(rapport.updated.size).to eq(1)
  end

  # La tâche doit pouvoir tourner deux fois : la seconde ne touche rien, et ne
  # réécrit surtout pas un poste corrigé à la main entre-temps.
  it "ne repasse pas sur une écriture déjà rangée" do
    entry = reglement(reference: "reprise-bar:2026-05")
    entry.update!(flow: "grocery")

    rapport = described_class.new(dry_run: false).run!

    expect(entry.reload.flow).to eq("grocery")
    expect(rapport.updated).to be_empty
    expect(rapport.untouched).to eq(1)
  end
end
