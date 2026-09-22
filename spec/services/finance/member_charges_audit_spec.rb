require "rails_helper"

# Issue #354 — voir le décalage d'un mois hérité de la reprise comptable.
#
# Toutes les dates sont figées : une spec qui s'appuie sur `Date.current` passe
# le jour où on l'écrit et casse une nuit plus tard.
RSpec.describe Finance::MemberChargesAudit do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Michael & Malau") }

  def charge(month, cents, year: 2026)
    account.account_entries.create!(entry_date: Date.new(year, month, -1), amount_cents: cents,
                                    flow: "charges", kind: "recurring", label: "Charges habitants")
  end

  def settle(month, cents, year: 2026, day: 5)
    account.account_entries.create!(entry_date: Date.new(year, month, day), amount_cents: -cents,
                                    flow: "charges", kind: "settlement", label: "Règlement")
  end

  def audit_for(account, year: 2026)
    described_class.new(year: year).run!.find { |a| a.account.id == account.id }
  end

  it "ne rend aucune ligne pour un compte sans charge sur l'année" do
    account.account_entries.create!(entry_date: Date.new(2026, 3, 4), amount_cents: 450,
                                    flow: "bar", kind: "bar", label: "Bière")

    expect(described_class.new(year: 2026).run!).to be_empty
  end

  it "ne signale rien sur un compte à jour" do
    (1..9).each { |month| charge(month, 30_000) }
    (1..9).each { |month| settle(month, 30_000) }

    audit = audit_for(account)

    expect(audit.cumulative_cents).to eq(0)
    expect(audit).not_to be_offset
  end

  # Le contrôle qui compte : une dette qui GRANDIT n'est pas un décalage, et ne
  # se répare pas en encodant une écriture manquante.
  it "ne signale pas une dette qui grandit" do
    (1..9).each { |month| charge(month, 30_000) }
    (1..3).each { |month| settle(month, 30_000) }

    audit = audit_for(account)

    expect(audit.cumulative_cents).to eq(180_000)
    expect(audit).not_to be_offset
  end

  # Le cas de Michael & Malau : le virement de janvier est parti en décembre,
  # la charge de janvier reste ouverte et le trou se décale, constant, toute
  # l'année.
  it "signale un écart cumulé constant sur trois mois ou plus" do
    charge(1, 30_000)
    (2..9).each { |month| charge(month, 34_500) }
    (2..9).each { |month| settle(month, 34_500) }

    audit = audit_for(account)

    expect(audit.cumulative_cents).to eq(30_000)
    expect(audit).to be_offset
    expect(audit.offset_run.amount_cents).to eq(30_000)
    expect(audit.offset_run.length).to eq(9)
    expect(audit.offset_run.from).to eq(Date.new(2026, 1, 1))
    expect(audit.offset_run.to).to eq(Date.new(2026, 9, 1))
  end

  # Les mois vides de la fin d'année ne sont pas une signature : l'année n'est
  # pas finie, elle est seulement inachevée.
  it "ne signale rien quand seuls les mois sans mouvement prolongent le cumul" do
    charge(1, 30_000)
    charge(2, 30_000)
    settle(2, 30_000)

    audit = audit_for(account)

    expect(audit.cumulative_cents).to eq(30_000)
    expect(audit).not_to be_offset
  end

  it "détaille chaque mois : facturé, réglé, écart, cumulé" do
    charge(1, 30_000)
    charge(2, 34_500)
    settle(2, 34_500)

    janvier, fevrier = audit_for(account).months.first(2)

    expect([janvier.billed_cents, janvier.settled_cents, janvier.delta_cents, janvier.cumulative_cents])
      .to eq([30_000, 0, 30_000, 30_000])
    expect([fevrier.billed_cents, fevrier.settled_cents, fevrier.delta_cents, fevrier.cumulative_cents])
      .to eq([34_500, 34_500, 0, 30_000])
  end

  # C'est l'AC qui raccroche l'audit au solde affiché : le cumul de décembre
  # vaut `balance_cents` moins tout ce qui ne relève pas des charges.
  it "recolle au solde du compte, une fois retiré ce qui ne relève pas des charges" do
    charge(1, 30_000)
    (2..9).each { |month| charge(month, 34_500) }
    (2..9).each { |month| settle(month, 34_500) }
    account.account_entries.create!(entry_date: Date.new(2026, 4, 2), amount_cents: 1_250,
                                    flow: "bar", kind: "bar", label: "Bière")

    audit = audit_for(account)
    hors_charges = account.account_entries.where.not(flow: "charges").sum(:amount_cents)

    expect(audit.cumulative_cents).to eq(account.reload.balance_cents - hors_charges)
  end

  # Une correction datée du 31 décembre doit éteindre le signal, sinon l'outil
  # continuerait d'accuser un compte réparé.
  it "reporte les charges d'avant l'année, correction du 31 décembre comprise" do
    settle(12, 30_000, year: 2025, day: 31)
    charge(1, 30_000)
    (2..9).each { |month| charge(month, 34_500) }
    (2..9).each { |month| settle(month, 34_500) }

    audit = audit_for(account)

    expect(audit.carried_cents).to eq(-30_000)
    expect(audit.cumulative_cents).to eq(0)
    expect(audit).not_to be_offset
  end

  it "se restreint aux comptes nommés" do
    charge(1, 30_000)
    autre = MemberAccount.create!(kind: "entity", name: "Semisto")
    autre.account_entries.create!(entry_date: Date.new(2026, 1, 31), amount_cents: 5_000,
                                  flow: "charges", kind: "recurring", label: "Charges")

    audits = described_class.new(year: 2026, codes: account.code).run!

    expect(audits.map { |a| a.account.code }).to eq([account.code])
  end

  it "ignore les comptes désactivés" do
    charge(1, 30_000)
    account.update!(active: false)

    expect(described_class.new(year: 2026).run!).to be_empty
  end

  describe "la charge de janvier" do
    it "est lue au grand livre" do
      charge(1, 30_000)

      audit = audit_for(account)

      expect(audit.january_charge_cents).to eq(30_000)
      expect(audit).to be_single_january_charge
    end

    it "n'est pas unique quand janvier porte deux charges" do
      charge(1, 20_000)
      charge(1, 10_000)

      expect(audit_for(account)).not_to be_single_january_charge
    end
  end
end
