require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

RSpec.describe ComplianceDeadlines::Generate do
  include FinanceBuilders

  let(:srl) { build_legal_entity(name: "SRL de test", form: "srl") }
  let(:today) { Date.new(2026, 9, 28) }
  let!(:tva) do
    ComplianceObligation.create!(title: "Déclaration TVA", legal_entity: srl, frequency: "quarterly",
                                 first_due_on: Date.new(2026, 4, 20))
  end

  def generate(horizon: Date.new(2027, 1, 31))
    described_class.new(horizon: horizon, today: today).run!
  end

  it "crée les échéances de la règle jusqu'à l'horizon" do
    report = generate

    expect(report.created).to eq(4)
    expect(tva.compliance_deadlines.ordered.map(&:display_title))
      .to eq(["Déclaration TVA — T1 2026", "Déclaration TVA — T2 2026", "Déclaration TVA — T3 2026", "Déclaration TVA — T4 2026"])
  end

  it "est idempotent" do
    generate

    expect(generate.created).to eq(0)
    expect(tva.compliance_deadlines.count).to eq(4)
  end

  # Une date avancée à la main pour cette fois ne doit pas être réécrite par la
  # règle à la nuit suivante.
  it "ne réécrit jamais une échéance existante" do
    generate
    t3 = tva.compliance_deadlines.find_by(period_start: Date.new(2026, 7, 1))
    t3.update!(due_on: Date.new(2026, 10, 15))

    generate

    expect(t3.reload.due_on).to eq(Date.new(2026, 10, 15))
  end

  describe "quand la règle change" do
    before { generate }

    it "retire les échéances futures qu'elle ne produit plus, si personne n'y a touché" do
      tva.update!(active: false)

      report = generate

      expect(report.removed).to eq(2)
      expect(tva.compliance_deadlines.pluck(:period_start)).to contain_exactly(Date.new(2026, 1, 1), Date.new(2026, 4, 1))
    end

    it "garde une échéance future sur laquelle quelqu'un a travaillé" do
      t4 = tva.compliance_deadlines.find_by(period_start: Date.new(2026, 10, 1))
      t4.update!(note: "Pièces demandées au comptable")
      tva.update!(active: false)

      generate

      expect(t4.reload).to be_present
      expect(tva.compliance_deadlines.count).to eq(3)
    end
  end
end
