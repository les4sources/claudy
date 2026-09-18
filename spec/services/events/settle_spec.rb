require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #245, phase 3 — le règlement d'un événement : le partage FIGÉ.
RSpec.describe Events::Settle do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank_general) { build_general_account(code: "550000", name: "Banque") }
  let!(:fee_account) { build_general_account(code: "616000", name: "Rémunérations d'intervenants", klass: 6, nature: "expense") }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:cash_account) { build_cash_account(entity, bank_general) }
  let!(:category) { EventCategory.create!(name: "Formation") }
  let!(:team) { Team.create!(name: "Transmission") }
  let!(:seb) { Human.create!(name: "Sébastien") }
  let!(:magali) { Human.create!(name: "Magali") }

  let(:event) do
    Event.create!(name: "Stage low-tech", event_category: category, team: team,
                  starts_at: Date.new(2026, 6, 10), ends_at: Date.new(2026, 6, 12),
                  starts_at_date: Date.new(2026, 6, 10), ends_at_date: Date.new(2026, 6, 12),
                  organizer_share_percent: 70)
  end

  def add_revenue(cents)
    entry = build_cash_entry(cash_account, amount_cents: cents)
    entry.cash_allocations.create!(general_account: bank_general, amount_cents: cents,
                                   legal_entity: entity, document: event)
  end

  def add_cost(cents, label: "Location de salle")
    EventCost.create!(event: event, label: label, amount_cents: cents, kind: "other")
  end

  def organize!(human, weight)
    EventOrganizer.create!(event: event, human: human, weight: weight)
  end

  describe "le calcul (décision 5)" do
    it "partage la base au taux, au prorata des poids, sans perdre un centime" do
      add_revenue(100_000)
      add_cost(30_000)
      organize!(seb, 2)
      organize!(magali, 1)

      calcul = Events::ShareCalculation.new(event.reload)
      expect(calcul.revenue_cents).to eq(100_000)
      expect(calcul.costs_cents).to eq(30_000)
      expect(calcul.base_cents).to eq(70_000)
      expect(calcul.organizers_cents).to eq(49_000)
      expect(calcul.house_cents).to eq(21_000)

      parts = calcul.lines.to_h { |l| [l.human.name, l.amount_cents] }
      expect(parts["Sébastien"]).to eq(32_667)
      expect(parts["Magali"]).to eq(16_333)
      expect(calcul.lines_total_cents).to eq(49_000)
    end

    it "ne fait rien payer aux organisateurs sur une base négative" do
      add_revenue(10_000)
      add_cost(30_000)
      organize!(seb, 1)

      calcul = Events::ShareCalculation.new(event.reload)
      expect(calcul.base_cents).to eq(-20_000)
      expect(calcul.organizers_cents).to eq(0)
      expect(calcul.house_cents).to eq(-20_000)
      expect(calcul.lines.map(&:amount_cents)).to eq([0])
    end

    it "ne produit aucune ligne sans organisateur" do
      add_revenue(100_000)
      expect(Events::ShareCalculation.new(event.reload).lines).to be_empty
    end
  end

  describe "le règlement" do
    before do
      add_revenue(100_000)
      add_cost(30_000)
      organize!(seb, 2)
      organize!(magali, 1)
    end

    it "fige les chiffres et crée une part par organisateur" do
      service = described_class.new(event: event.reload)
      expect(service.run).to be(true)

      settlement = event.reload.event_settlement
      expect(settlement.revenue_cents).to eq(100_000)
      expect(settlement.costs_cents).to eq(30_000)
      expect(settlement.base_cents).to eq(70_000)
      expect(settlement.organizer_share_percent).to eq(70)
      expect(settlement.organizers_cents).to eq(49_000)
      expect(settlement.house_cents).to eq(21_000)
      expect(settlement).to be_issued
      expect(settlement.event_settlement_lines.sum(:amount_cents)).to eq(49_000)
    end

    it "passe l'écriture : une charge avec le pôle, une ligne 440000 par organisateur" do
      described_class.new(event: event.reload).run
      settlement = event.reload.event_settlement

      entry = JournalEntry.unscoped.find_by(source: settlement, journal: "purchases")
      expect(entry).to be_present
      expect(settlement.posted_at).to be_present

      charge = entry.journal_lines.select { |l| l.debit_cents.to_i.positive? }
      expect(charge.size).to eq(1)
      expect(charge.first.general_account.code).to eq("616000")
      expect(charge.first.debit_cents).to eq(49_000)
      expect(charge.first.team).to eq(team)

      credits = entry.journal_lines.select { |l| l.credit_cents.to_i.positive? }
      expect(credits.size).to eq(2)
      expect(credits.map { |l| l.general_account.code }.uniq).to eq(["440000"])
      expect(credits.map(&:credit_cents).sum).to eq(49_000)
      expect(credits.map { |l| l.third_party&.name }).to match_array(["Sébastien", "Magali"])
    end

    it "refuse de régler deux fois" do
      described_class.new(event: event.reload).run

      second = described_class.new(event: event.reload)
      expect(second.run).to be(false)
      expect(second.error_message).to eq(described_class::ALREADY_SETTLED)
      expect(EventSettlement.count).to eq(1)
    end

    it "refuse un événement sans organisateur" do
      event.event_organizers.destroy_all
      service = described_class.new(event: event.reload)
      expect(service.run).to be(false)
      expect(service.error_message).to eq(described_class::NOTHING_TO_SHARE)
    end

    it "refuse quand la part des organisateurs est nulle" do
      event.event_costs.destroy_all
      add_cost(100_000)
      service = described_class.new(event: event.reload)
      expect(service.run).to be(false)
      expect(service.error_message).to eq(described_class::NO_SHARE)
      expect(EventSettlement.count).to eq(0)
    end
  end

  describe "l'événement réglé ne bouge plus" do
    before do
      add_revenue(100_000)
      organize!(seb, 1)
      described_class.new(event: event.reload).run
    end

    it "refuse une recette rattachée après le règlement" do
      entry = build_cash_entry(cash_account, amount_cents: 5_000)
      allocation = entry.cash_allocations.build(general_account: bank_general, amount_cents: 5_000,
                                                legal_entity: entity, document: event.reload)

      expect(allocation).not_to be_valid
      expect(allocation.errors[:document].join).to include("contre-passation")
    end

    it "relit les chiffres figés plutôt que de recalculer" do
      settlement = event.reload.event_settlement
      EventCost.create!(event: event, label: "Frais tardif", amount_cents: 50_000, kind: "other")

      calcul = Events::ShareCalculation.for_settlement(settlement.reload)
      expect(calcul.costs_cents).to eq(0)
      expect(calcul.organizers_cents).to eq(70_000)
    end
  end

  describe "le rapprochement" do
    let!(:settlement) do
      add_revenue(100_000)
      organize!(seb, 2)
      organize!(magali, 1)
      described_class.new(event: event.reload).run
      event.reload.event_settlement
    end

    it "solde une part et note la date, sans régler le tout" do
      line = settlement.event_settlement_lines.find_by(human: seb)
      entry = build_cash_entry(cash_account, amount_cents: -line.amount_cents, label: "Virement Sébastien")
      entry.cash_allocations.create!(general_account: supplier_account, amount_cents: -line.amount_cents,
                                     legal_entity: entity, document: line)

      expect(line.reload).to be_payable_settled
      expect(line.paid_on).to eq(entry.entry_date)
      expect(settlement.reload).to be_issued
    end

    it "passe le règlement en payé quand toutes les parts sont virées" do
      settlement.event_settlement_lines.each do |line|
        entry = build_cash_entry(cash_account, amount_cents: -line.amount_cents, label: "Virement")
        entry.cash_allocations.create!(general_account: supplier_account, amount_cents: -line.amount_cents,
                                       legal_entity: entity, document: line)
      end

      expect(settlement.reload).to be_paid
    end
  end
end
