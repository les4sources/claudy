require "rails_helper"

# Issue #159 — génération mensuelle des charges récurrentes.
RSpec.describe Finance::GenerateRecurringCharges do
  let(:household) { Household.create!(name: "Famille Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let(:account) do
    MemberAccount.create!(kind: "household", household: household, name: "Famille Chevêche")
  end

  def add_member(name, kind, started_on: Date.new(2023, 1, 1), ended_on: nil)
    household.household_members.create!(name: name, kind: kind, started_on: started_on, ended_on: ended_on)
  end

  def seed_rate(key, cents, active_from: Date.new(2023, 1, 1), active_until: nil)
    rate = Rate.find_or_create_by!(key: key) { |r| r.amount_cents = cents; r.unit = "cents" }
    rate.rate_versions.create!(amount_cents: cents, active_from: active_from, active_until: active_until)
    rate
  end

  describe "idempotence" do
    let!(:charge) do
      RecurringCharge.create!(member_account: account, label: "Forfait dôme", basis: "flat",
                              amount_cents: 5000, flow: "dome", starts_on: Date.new(2023, 1, 1))
    end

    it "crée l'écriture du mois" do
      expect {
        described_class.new(month: "2026-08").run!
      }.to change(AccountEntry, :count).by(1)
    end

    # L'idempotence tient à l'index unique, pas à un `exists?` en Ruby : c'est ce
    # qui la rend vraie même en génération concurrente.
    it "ne crée rien à la seconde exécution du même mois" do
      described_class.new(month: "2026-08").run!

      expect {
        described_class.new(month: "2026-08").run!
      }.not_to change(AccountEntry, :count)
    end

    it "reste bloquée même si le garde-fou Ruby est contourné" do
      described_class.new(month: "2026-08").run!
      cle = AccountEntry.last.idempotency_key

      doublon = AccountEntry.new(member_account: account, entry_date: Date.new(2026, 8, 31),
                                 amount_cents: 5000, idempotency_key: cle)

      expect { doublon.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "génère un mois différent sans se confondre" do
      described_class.new(month: "2026-08").run!

      expect {
        described_class.new(month: "2026-09").run!
      }.to change(AccountEntry, :count).by(1)
    end

    it "date l'écriture au dernier jour du mois" do
      described_class.new(month: "2026-08").run!

      expect(AccountEntry.last.entry_date).to eq(Date.new(2026, 8, 31))
    end
  end

  describe "base par adulte, datée" do
    before do
      seed_rate("pot.monthly_per_adult", 1000)
      add_member("Ada", "adult")
      add_member("Bob", "adult", started_on: Date.new(2026, 6, 1))
      RecurringCharge.create!(member_account: account, label: "Cagnotte", basis: "per_adult",
                              rate_key: "pot.monthly_per_adult", flow: "pot", starts_on: Date.new(2023, 1, 1))
    end

    # Recompter un mois passé ne doit pas mentir : en mars 2026 il n'y avait
    # qu'un adulte, en juillet il y en a deux.
    it "compte les adultes DU MOIS traité" do
      described_class.new(month: "2026-03").run!
      expect(AccountEntry.last.amount_cents).to eq(1000)

      described_class.new(month: "2026-07").run!
      expect(AccountEntry.last.amount_cents).to eq(2000)
    end
  end

  # LE critère de la phase : la part balançoire s'éteint toute seule au
  # 30 avril 2027, sans changement de code et sans déploiement à cette date.
  describe "cagnotte scindée" do
    before do
      seed_rate("pot.monthly_per_adult", 1000)
      seed_rate("pot.swing_share", 500, active_until: Date.new(2027, 4, 30))
      add_member("Ada", "adult")
      RecurringCharge.create!(member_account: account, label: "Cagnotte", basis: "per_adult",
                              rate_key: "pot.monthly_per_adult", split_rate_key: "pot.swing_share",
                              split_label: "Balançoire — Magali", flow: "pot", starts_on: Date.new(2023, 1, 1))
    end

    it "produit DEUX lignes tant que la part scindée est en vigueur" do
      described_class.new(month: "2027-04").run!

      entries = AccountEntry.where(member_account: account).order(:id)
      expect(entries.count).to eq(2)
      expect(entries.map(&:amount_cents)).to contain_exactly(500, 500)
      expect(entries.map(&:label)).to include("Balançoire — Magali")
    end

    it "produit UNE seule ligne dès que la part scindée est close" do
      described_class.new(month: "2027-05").run!

      entries = AccountEntry.where(member_account: account)
      expect(entries.count).to eq(1)
      expect(entries.first.amount_cents).to eq(1000)
    end

    it "ne change pas le total dû au passage" do
      described_class.new(month: "2027-04").run!
      avril = AccountEntry.where(member_account: account).sum(:amount_cents)

      AccountEntry.delete_all
      described_class.new(month: "2027-05").run!
      mai = AccountEntry.where(member_account: account).sum(:amount_cents)

      expect(mai).to eq(avril)
    end
  end

  describe "cas ignorés" do
    it "ne crée AUCUNE écriture quand la clé de barème ne résout rien" do
      RecurringCharge.create!(member_account: account, label: "Charge fantôme", basis: "flat",
                              rate_key: "cle.inexistante", starts_on: Date.new(2023, 1, 1))

      report = nil
      expect { report = described_class.new(month: "2026-08").run! }.not_to change(AccountEntry, :count)
      expect(report.skipped.first[:reason]).to include("non résolu")
    end

    it "ignore une charge hors période" do
      RecurringCharge.create!(member_account: account, label: "Terminée", basis: "flat", amount_cents: 1000,
                              starts_on: Date.new(2023, 1, 1), ends_on: Date.new(2025, 12, 31))

      expect { described_class.new(month: "2026-08").run! }.not_to change(AccountEntry, :count)
    end

    it "ignore une charge désactivée" do
      RecurringCharge.create!(member_account: account, label: "En pause", basis: "flat", amount_cents: 1000,
                              starts_on: Date.new(2023, 1, 1), active: false)

      expect { described_class.new(month: "2026-08").run! }.not_to change(AccountEntry, :count)
    end

    it "ignore un ménage sans adulte sur le mois plutôt que d'écrire zéro" do
      seed_rate("pot.monthly_per_adult", 1000)
      RecurringCharge.create!(member_account: account, label: "Cagnotte", basis: "per_adult",
                              rate_key: "pot.monthly_per_adult", starts_on: Date.new(2023, 1, 1))

      report = nil
      expect { report = described_class.new(month: "2026-08").run! }.not_to change(AccountEntry, :count)
      expect(report.skipped).to be_present
    end
  end

  describe "dry-run" do
    before do
      RecurringCharge.create!(member_account: account, label: "Forfait dôme", basis: "flat",
                              amount_cents: 5000, starts_on: Date.new(2023, 1, 1))
    end

    it "n'écrit rien mais annonce ce qui serait créé" do
      report = nil

      expect { report = described_class.new(month: "2026-08", dry_run: true).run! }
        .not_to change(AccountEntry, :count)

      expect(report.created.size).to eq(1)
      expect(report.total_cents).to eq(5000)
    end
  end

  # Le forfait charges vaut pour TOUS les ménages habitants. Une règle, pas une
  # par famille : sinon la prochaine arrivée est oubliée.
  describe "périmètre de ménages" do
    let(:autre_menage) { Household.create!(name: "Hulotte", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
    let!(:autre_compte) { MemberAccount.create!(kind: "household", household: autre_menage, name: "Hulotte") }
    let!(:menage_membre) { Household.create!(name: "Grand-Duc", kind: "member", moved_in_on: Date.new(2023, 1, 1)) }
    let!(:compte_membre) { MemberAccount.create!(kind: "household", household: menage_membre, name: "Grand-Duc") }

    before do
      account # `let` paresseux : sans cette ligne le compte n'existe pas encore
              # quand la génération résout le périmètre, et le test passe à côté.
      seed_rate("charges.per_person_monthly", 6500, active_from: Date.new(2026, 2, 1))
      add_member("Ada", "adult")
      add_member("Zoé", "child")
      autre_menage.household_members.create!(name: "Bob", kind: "adult", started_on: Date.new(2023, 1, 1))
      menage_membre.household_members.create!(name: "Cléo", kind: "adult", started_on: Date.new(2023, 1, 1))

      RecurringCharge.create!(label: "Charges habitants", basis: "per_person",
                              applies_to: "resident_households",
                              rate_key: "charges.per_person_monthly", flow: "charges",
                              starts_on: Date.new(2026, 2, 1))
    end

    it "écrit sur TOUS les ménages habitants, et sur eux seuls" do
      described_class.new(month: "2026-08").run!

      expect(AccountEntry.where(member_account: account).sum(:amount_cents)).to eq(13_000) # 2 personnes
      expect(AccountEntry.where(member_account: autre_compte).sum(:amount_cents)).to eq(6_500) # 1 personne
      expect(AccountEntry.where(member_account: compte_membre)).to be_empty # ménage membre
    end

    it "compte les ENFANTS aussi — 65 € par personne, pas par adulte" do
      described_class.new(month: "2026-08").run!

      expect(AccountEntry.where(member_account: account).count).to eq(1)
      expect(AccountEntry.where(member_account: account).first.amount_cents).to eq(13_000)
    end

    it "ne duplique rien à la seconde exécution" do
      described_class.new(month: "2026-08").run!

      expect { described_class.new(month: "2026-08").run! }.not_to change(AccountEntry, :count)
    end

    # LA raison d'être du périmètre : la famille arrivée après coup est couverte
    # sans que personne n'ait touché à la règle.
    it "couvre un ménage créé APRÈS la règle" do
      described_class.new(month: "2026-08").run!

      nouveau = Household.create!(name: "Chevêchette", kind: "resident", moved_in_on: Date.new(2026, 9, 1))
      nouveau.household_members.create!(name: "Dan", kind: "adult", started_on: Date.new(2026, 9, 1))
      compte = MemberAccount.create!(kind: "household", household: nouveau, name: "Chevêchette")

      described_class.new(month: "2026-09").run!

      expect(AccountEntry.where(member_account: compte).sum(:amount_cents)).to eq(6_500)
    end

    # La règle démarre au 01/02/2026 : janvier n'est pas « ignoré », il est HORS
    # PÉRIODE. Rien n'est écrit, et c'est la date de début qui protège — pas le
    # barème.
    it "n'écrit rien sur un mois antérieur à la règle" do
      report = described_class.new(month: "2026-01").run!

      expect(AccountEntry.count).to eq(0)
      expect(report.created).to be_empty
    end

    # En revanche, une règle DÉJÀ active dont le barème n'est pas encore en
    # vigueur doit être signalée, pas facturée à zéro.
    it "signale une règle active dont le barème ne résout rien" do
      RecurringCharge.create!(label: "Charges anticipées", basis: "per_person",
                              applies_to: "resident_households",
                              rate_key: "charges.inexistante", flow: "charges",
                              starts_on: Date.new(2023, 1, 1))

      report = described_class.new(month: "2026-08").run!

      expect(report.skipped.map { |l| l[:charge].label }).to include("Charges anticipées")
    end
  end

  it "trace les écritures générées comme telles" do
    RecurringCharge.create!(member_account: account, label: "Forfait dôme", basis: "flat",
                            amount_cents: 5000, starts_on: Date.new(2023, 1, 1))

    described_class.new(month: "2026-08").run!

    expect(AccountEntry.last.source).to eq("recurring")
  end
end
