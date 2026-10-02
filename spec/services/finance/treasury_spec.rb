require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La trésorerie de la Fondation (2026-09-29). Trois façons de mentir sont
# verrouillées ici : additionner un solde que rien ne vérifie, compter deux fois
# un même montant, et projeter un retard comme une entrée certaine.
RSpec.describe Finance::Treasury do
  include FinanceBuilders

  let(:today) { Date.new(2026, 9, 29) }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let(:bank_general) { build_general_account(code: "550000", name: "Triodos") }
  let(:cash_general) { build_general_account(code: "570000", name: "Caisse") }
  let!(:bank) { build_cash_account(entity, bank_general, name: "Triodos") }
  let(:customer) { Customer.create!(first_name: "Jeanne", last_name: "Dupont", email: "jeanne@example.test") }

  subject(:treasury) { described_class.new(legal_entity: entity, today: today) }

  def coda_statement(account, balance_cents:, on:)
    import = CodaImport.create!(filename: "releve-#{on}.cod", sha256: SecureRandom.hex(32), content: "x")
    CodaStatement.create!(coda_import: import, cash_account: account, sequence_number: SecureRandom.hex(2),
                          period_year: on.year, old_balance_cents: 0, new_balance_cents: balance_cents,
                          new_balance_date: on)
  end

  def stay(arrival:, departure:, total:, status: "confirmed")
    Stay.create!(customer: customer, arrival_date: arrival, departure_date: departure,
                 total_amount_cents: total, payment_status: "pending", status: status)
  end

  def pay(stay, cents)
    Payment.create!(stay: stay, amount_cents: cents, status: "paid", payment_method: "bank_transfer")
  end

  describe "le solde" do
    it "se cale sur le solde du dernier relevé CODA, pas sur la somme brute des lignes" do
      build_cash_entry(bank, amount_cents: 100_000, entry_date: Date.new(2026, 8, 1))
      build_cash_entry(bank, amount_cents: -30_000, entry_date: Date.new(2026, 9, 5))
      # Le relevé dit 75 000 : 5 000 d'ouverture qu'aucune ligne ne porte.
      coda_statement(bank, balance_cents: 75_000, on: Date.new(2026, 9, 10))

      expect(treasury.balance_cents).to eq(75_000)
      expect(treasury.as_of).to eq(Date.new(2026, 9, 10))
      # Le recalage vaut pour tout l'historique : entre les deux lignes, 5 000 + 100 000.
      point = treasury.history.select { |p| p.date >= Date.new(2026, 8, 1) && p.date < Date.new(2026, 9, 5) }.last
      expect(point.balance_cents).to eq(105_000)
      expect(treasury.history.last.date).to eq(today)
    end

    it "laisse hors du total une caisse jamais comptée, sans la cacher" do
      coda_statement(bank, balance_cents: 50_000, on: Date.new(2026, 9, 10))
      caisse = build_cash_account(entity, cash_general, name: "Caisse du domaine", kind: "cash")
      build_cash_entry(caisse, amount_cents: 1_630_000, entry_date: Date.new(2026, 6, 3))

      expect(treasury.balance_cents).to eq(50_000)
      expect(treasury.unanchored_accounts.map(&:account)).to eq([caisse])
      expect(treasury.unanchored_accounts.first.balance_cents).to eq(1_630_000)
    end

    it "additionne la caisse dès qu'un comptage validé l'ancre" do
      coda_statement(bank, balance_cents: 50_000, on: Date.new(2026, 9, 10))
      caisse = build_cash_account(entity, cash_general, name: "Caisse du domaine", kind: "cash")
      build_cash_entry(caisse, amount_cents: 20_000, entry_date: Date.new(2026, 9, 1))
      CashCount.create!(cash_account: caisse, counted_on: Date.new(2026, 9, 20), counted_cents: 12_000,
                        status: "validated")

      expect(treasury.balance_cents).to eq(62_000)
      expect(treasury.anchored_accounts.map(&:account)).to contain_exactly(bank, caisse)
    end

    it "ignore les lignes exclues" do
      build_cash_entry(bank, amount_cents: 10_000, entry_date: Date.new(2026, 9, 1))
      coda_statement(bank, balance_cents: 10_000, on: Date.new(2026, 9, 2))
      build_cash_entry(bank, amount_cents: 99_000, entry_date: Date.new(2026, 9, 3))
        .update!(status: "excluded", excluded_reason: "doublon")

      expect(treasury.balance_cents).to eq(10_000)
    end
  end

  describe "ce qui doit rentrer" do
    before { coda_statement(bank, balance_cents: 0, on: Date.new(2026, 9, 10)) }

    it "attend le reste dû d'un séjour confirmé à sa date d'arrivée" do
      a_venir = stay(arrival: Date.new(2026, 10, 10), departure: Date.new(2026, 10, 12), total: 80_000)
      pay(a_venir, 20_000)

      expect(treasury.upcoming_receivables.map { |r| [r.stay, r.due_on, r.amount_cents] })
        .to eq([[a_venir, Date.new(2026, 10, 10), 60_000]])
      expect(treasury.incoming_cents).to eq(60_000)
    end

    it "attend aujourd'hui le reste dû d'un séjour déjà commencé" do
      en_cours = stay(arrival: Date.new(2026, 9, 27), departure: Date.new(2026, 10, 1), total: 40_000)

      expect(treasury.upcoming_receivables.first.due_on).to eq(today)
      expect(treasury.upcoming_receivables.first.stay).to eq(en_cours)
    end

    it "ignore les séjours soldés, annulés, en attente ou refusés" do
      solde = stay(arrival: Date.new(2026, 10, 10), departure: Date.new(2026, 10, 12), total: 30_000)
      pay(solde, 30_000)
      stay(arrival: Date.new(2026, 10, 10), departure: Date.new(2026, 10, 12), total: 30_000, status: "canceled")
      stay(arrival: Date.new(2026, 10, 10), departure: Date.new(2026, 10, 12), total: 30_000, status: "pending")
      stay(arrival: Date.new(2026, 10, 10), departure: Date.new(2026, 10, 12), total: 30_000, status: "declined")

      expect(treasury.upcoming_receivables).to be_empty
    end

    it "compte un séjour pré-confirmé : l'équipe s'est engagée sur les dates" do
      stay(arrival: Date.new(2026, 10, 10), departure: Date.new(2026, 10, 12), total: 30_000, status: "pre_confirmed")

      expect(treasury.incoming_cents).to eq(30_000)
    end

    it "ne place pas le point bas au-dessus du solde quand un séjour arrive aujourd'hui" do
      stay(arrival: today, departure: today + 2, total: 10_500)

      expect(treasury.lowest_point.balance_cents).to eq(0)
    end

    it "liste un séjour au-delà de l'horizon sans le projeter" do
      stay(arrival: Date.new(2027, 3, 1), departure: Date.new(2027, 3, 3), total: 50_000)

      expect(treasury.upcoming_receivables.size).to eq(1)
      expect(treasury.incoming_cents).to eq(0)
    end

    it "liste un retard de moins d'un an sans le projeter" do
      en_retard = stay(arrival: Date.new(2026, 7, 1), departure: Date.new(2026, 7, 3), total: 25_000)

      expect(treasury.late_receivables.map(&:stay)).to eq([en_retard])
      expect(treasury.incoming_cents).to eq(0)
      expect(treasury.stale_receivables).to be_empty
    end

    it "range à assainir un reste dû de plus d'un an" do
      vieux = stay(arrival: Date.new(2024, 7, 1), departure: Date.new(2024, 7, 3), total: 25_000)

      expect(treasury.stale_receivables.map(&:stay)).to eq([vieux])
      expect(treasury.late_receivables).to be_empty
    end
  end

  describe "ce qui doit sortir, et la projection" do
    let(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
    let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
    let(:tiers) { ThirdParty.create!(name: "Antargaz", kind: "supplier", iban: "BE68539007547034") }

    before do
      build_fiscal_year(entity)
      coda_statement(bank, balance_cents: 100_000, on: Date.new(2026, 9, 10))
    end

    def facture(total:, due_on:, entity: self.entity, number: "F-#{SecureRandom.hex(2)}")
      f = PurchaseInvoice.create!(legal_entity: entity, third_party: tiers, number: number,
                                 issued_on: Date.new(2026, 9, 1), due_on: due_on, total_cents: total)
      f.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
      PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
    end

    it "retire une dette à son échéance, et une dette échue aujourd'hui" do
      facture(total: 30_000, due_on: Date.new(2026, 10, 20))
      facture(total: 5_000, due_on: Date.new(2026, 9, 1))

      expect(treasury.outflows.map { |o| [o.due_on, o.amount_cents] })
        .to contain_exactly([today, 5_000], [Date.new(2026, 10, 20), 30_000])
      expect(treasury.outgoing_cents).to eq(35_000)
    end

    it "ne retire pas la dette d'une autre entité" do
      srl = build_legal_entity(name: "Domaine SRL", form: "srl")
      build_fiscal_year(srl)
      facture(total: 30_000, due_on: Date.new(2026, 10, 20), entity: srl)

      expect(treasury.outflows).to be_empty
    end

    describe "les charges fixes" do
      def charge(**attributes)
        RecurringExpense.create!({ legal_entity: entity, label: "Voo", amount_cents: 6_776, frequency: "monthly",
                                   first_due_on: Date.new(2026, 1, 27), third_party: tiers }.merge(attributes))
      end

      it "retire chaque occurrence de l'horizon à sa date" do
        voo = charge

        expect(treasury.outflows.map { |o| [o.recurring_expense, o.due_on, o.amount_cents] }).to eq([
          [voo, Date.new(2026, 10, 27), 6_776],
          [voo, Date.new(2026, 11, 27), 6_776],
          [voo, Date.new(2026, 12, 27), 6_776]
        ])
        expect(treasury.outgoing_cents).to eq(3 * 6_776)
      end

      it "s'efface quand la vraie facture du même tiers couvre la période" do
        charge
        facture(total: 7_000, due_on: Date.new(2026, 11, 20))

        expect(treasury.outflows.map { |o| [o.recurring?, o.due_on, o.amount_cents] }).to eq([
          [true, Date.new(2026, 10, 27), 6_776],
          [false, Date.new(2026, 11, 20), 7_000],
          [true, Date.new(2026, 12, 27), 6_776]
        ])
      end

      it "reste estimée sans fournisseur, même quand une facture tombe le même mois" do
        charge(third_party: nil)
        facture(total: 7_000, due_on: Date.new(2026, 11, 20))

        expect(treasury.outflows.count(&:recurring?)).to eq(3)
      end

      it "ignore une charge inactive, terminée ou d'une autre entité" do
        srl = build_legal_entity(name: "Domaine SRL", form: "srl")
        charge(active: false)
        charge(label: "Ancien contrat", ends_on: Date.new(2026, 9, 1))
        charge(label: "SRL", legal_entity: srl)

        expect(treasury.outflows).to be_empty
      end
    end

    it "dessine des marches et trouve le point bas" do
      facture(total: 150_000, due_on: Date.new(2026, 10, 5))
      stay(arrival: Date.new(2026, 10, 20), departure: Date.new(2026, 10, 22), total: 80_000)

      expect(treasury.projection.map { |p| [p.date, p.balance_cents] }).to eq([
        [today, 100_000],
        [Date.new(2026, 10, 5), -50_000],
        [Date.new(2026, 10, 20), 30_000],
        [today + 90, 30_000]
      ])
      expect(treasury.lowest_point.balance_cents).to eq(-50_000)
      expect(treasury.lowest_point.date).to eq(Date.new(2026, 10, 5))
    end
  end

  it "ne trouve rien à lire sans fondation active" do
    entity.update!(form: "srl")

    expect(described_class.for_foundation).to be_nil
  end
end
