require "rails_helper"

# Issue #160 — émission d'un décompte. C'est le moment où des chiffres cessent
# d'être un affichage pour devenir un document : ces specs vérifient qu'il ne
# peut pas mentir.
RSpec.describe Finance::IssueStatement do
  include ActiveSupport::Testing::TimeHelpers

  let(:household) { Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  def add_entry(date, cents, **attrs)
    account.account_entries.create!(entry_date: date, amount_cents: cents, label: "Ligne", **attrs)
  end

  def issue(month) = described_class.new(member_account: account, month: month).run!

  describe "gel des montants" do
    before do
      add_entry(Date.new(2026, 7, 10), 1500)
      add_entry(Date.new(2026, 7, 20), 500)
      add_entry(Date.new(2026, 7, 25), -800)
    end

    it "fige ouverture, débits, crédits et clôture" do
      statement = issue("2026-07")

      expect(statement.opening_balance_cents).to eq(0)
      expect(statement.debits_cents).to eq(2000)
      expect(statement.credits_cents).to eq(-800)
      expect(statement.closing_balance_cents).to eq(1200)
    end

    it "verrouille les écritures couvertes" do
      issue("2026-07")

      expect(account.account_entries.reload).to all(be_locked)
    end

    it "ne rattache pas une écriture d'un autre mois" do
      add_entry(Date.new(2026, 8, 3), 999)

      statement = issue("2026-07")

      expect(statement.account_entries.count).to eq(3)
      expect(statement.closing_balance_cents).to eq(1200)
    end

    it "reprend le solde d'ouverture du compte quand il n'y a pas de décompte précédent" do
      account.update!(opening_balance_cents: 5000)

      expect(issue("2026-07").opening_balance_cents).to eq(5000)
    end
  end

  # L'invariant qui rend la chaîne auditable de bout en bout.
  describe "chaînage sur trois mois" do
    it "ouvre chaque mois là où le précédent s'est fermé" do
      add_entry(Date.new(2026, 7, 15), 1000)
      add_entry(Date.new(2026, 8, 15), 2000)
      add_entry(Date.new(2026, 9, 15), -500)

      juillet = issue("2026-07")
      aout = issue("2026-08")
      septembre = issue("2026-09")

      expect(juillet.closing_balance_cents).to eq(1000)
      expect(aout.opening_balance_cents).to eq(1000)
      expect(aout.closing_balance_cents).to eq(3000)
      expect(septembre.opening_balance_cents).to eq(3000)
      expect(septembre.closing_balance_cents).to eq(2500)
    end
  end

  describe "charges récurrentes non générées" do
    before do
      Rate.create!(key: "pot.monthly_per_adult", amount_cents: 1000, unit: "cents")
          .rate_versions.create!(amount_cents: 1000, active_from: Date.new(2023, 1, 1))
      household.household_members.create!(name: "Ada", kind: "adult", started_on: Date.new(2023, 1, 1))
      RecurringCharge.create!(member_account: account, label: "Cagnotte", basis: "per_adult",
                              rate_key: "pot.monthly_per_adult", starts_on: Date.new(2023, 1, 1))
    end

    # Émettre un décompte incomplet est pire que ne pas l'émettre : le sourcier
    # paie, se croit quitte, et redécouvre sa cagnotte le mois suivant.
    it "refuse l'émission" do
      expect { issue("2026-07") }.to raise_error(described_class::RecurringChargesMissing, /Cagnotte/)
    end

    it "n'écrit aucun décompte au passage" do
      expect { issue("2026-07") rescue nil }.not_to change(AccountStatement, :count)
    end

    it "accepte une fois les charges générées" do
      Finance::GenerateRecurringCharges.new(month: "2026-07").run!

      expect(issue("2026-07").closing_balance_cents).to eq(1000)
    end
  end

  describe "double émission" do
    before { add_entry(Date.new(2026, 7, 10), 1000) }

    it "refuse la seconde" do
      issue("2026-07")

      expect { issue("2026-07") }.to raise_error(described_class::AlreadyIssued)
    end

    it "ne produit qu'un seul décompte" do
      issue("2026-07")
      begin
        issue("2026-07")
      rescue described_class::AlreadyIssued
        nil
      end

      expect(AccountStatement.where(member_account: account, period_month: Date.new(2026, 7, 1)).count).to eq(1)
    end

    # L'index unique est la vraie garantie : le verrou seul laisserait passer
    # deux processus arrivés exactement en même temps.
    it "est verrouillée par la base, pas seulement par le service" do
      issue("2026-07")

      doublon = AccountStatement.new(member_account: account, period_month: Date.new(2026, 7, 1),
                                     token: SecureRandom.hex(8))

      expect { doublon.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "après émission" do
    before do
      add_entry(Date.new(2026, 7, 10), 1000)
      issue("2026-07")
    end

    it "l'écriture couverte refuse toute modification" do
      expect { account.account_entries.first.update!(amount_cents: 9999) }
        .to raise_error(AccountEntry::Locked)
    end

    it "la contre-écriture reste possible et tombe hors du décompte figé" do
      contre = account.account_entries.first.reverse!

      expect(contre.amount_cents).to eq(-1000)
      expect(contre.account_statement_id).to be_nil
      expect(AccountStatement.last.closing_balance_cents).to eq(1000)
    end
  end

  # 2026-11-02 — les décomptes d'octobre ont été émis le 27, avant la feuille
  # de bar et les charges du 31.
  describe "mois pas terminé" do
    before { add_entry(Date.new(2026, 7, 10), 1000) }

    it "refuse d'émettre avant le dernier jour passé" do
      travel_to(Date.new(2026, 7, 31)) do
        expect { issue("2026-07") }.to raise_error(described_class::MonthNotOver, /juillet 2026 n'est pas terminé/i)
      end
    end

    it "accepte dès le premier du mois suivant" do
      travel_to(Date.new(2026, 8, 1)) do
        expect(issue("2026-07").closing_balance_cents).to eq(1000)
      end
    end
  end

  # La règle « tous les ménages » (charges habitants, cagnotte, balançoire)
  # n'a pas de compte propre : l'ancien contrôle ne la voyait pas.
  describe "charge de périmètre non générée" do
    before do
      account # le ménage existe avant que la règle ne se déplie
      RecurringCharge.create!(label: "Charges habitants", basis: "flat", amount_cents: 32_500, flow: "charges",
                              applies_to: "resident_households", starts_on: Date.new(2023, 1, 1))
    end

    it "refuse l'émission tant qu'elle n'est pas générée pour ce compte" do
      expect { issue("2026-07") }.to raise_error(described_class::RecurringChargesMissing, /Charges habitants/)
    end

    it "accepte une fois générée" do
      Finance::GenerateRecurringCharges.new(month: "2026-07").run!

      expect(issue("2026-07").closing_balance_cents).to eq(32_500)
    end
  end

  # Une ligne datée d'un mois déjà couvert, posée après l'émission (un
  # règlement rapproché après coup porte la date du virement), ne tombe plus
  # dans le vide : le décompte suivant la reprend.
  describe "lignes arrivées après l'émission" do
    it "passent sur le décompte suivant, qui recolle au grand livre" do
      add_entry(Date.new(2026, 6, 20), 400)
      add_entry(Date.new(2026, 7, 10), 1000)
      juillet = issue("2026-07")
      expect(juillet.opening_balance_cents).to eq(400)

      travel_to(1.minute.from_now) do
        add_entry(Date.new(2026, 7, 31), 300)   # le bar de juillet, posé en retard
        add_entry(Date.new(2026, 3, 4), -5000)  # un règlement de mars rapproché après coup
      end
      add_entry(Date.new(2026, 8, 12), 200)

      aout = issue("2026-08")

      expect(aout.opening_balance_cents).to eq(1400)
      expect(aout.debits_cents).to eq(500)
      expect(aout.credits_cents).to eq(-5000)
      expect(aout.closing_balance_cents).to eq(account.reload.balance_cents)
      expect(aout.account_entries.count).to eq(3)
    end

    it "ne recompte pas ce que l'ouverture du premier décompte contenait déjà" do
      add_entry(Date.new(2026, 6, 20), 400)
      issue("2026-07")
      add_entry(Date.new(2026, 8, 12), 200)

      aout = issue("2026-08")

      expect(aout.debits_cents).to eq(200)
      expect(aout.closing_balance_cents).to eq(600)
    end
  end

  describe ".bar_missing?" do
    it "avertit quand un compte qui a du bar d'habitude n'en a aucun ce mois-ci" do
      add_entry(Date.new(2026, 9, 30), 800, flow: "bar", kind: "bar")

      expect(described_class.bar_missing?(account, Date.new(2026, 10, 1))).to be(true)
      add_entry(Date.new(2026, 10, 31), 500, flow: "bar", kind: "bar")
      expect(described_class.bar_missing?(account, Date.new(2026, 10, 1))).to be(false)
    end

    it "se tait pour un compte qui ne prend jamais rien au bar" do
      add_entry(Date.new(2026, 9, 30), -800, flow: "bar", kind: "settlement")

      expect(described_class.bar_missing?(account, Date.new(2026, 10, 1))).to be(false)
    end
  end
end
