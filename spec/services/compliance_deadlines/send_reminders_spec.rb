require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

RSpec.describe ComplianceDeadlines::SendReminders do
  include FinanceBuilders

  let(:michael) { User.create!(email: "michael-rappels@les4sources.be", password: "password123") }
  let(:ssi) { build_legal_entity(name: "Société simple de test", form: "simple_company") }
  let(:obligation) do
    ComplianceObligation.create!(title: "Assurance incendie", legal_entity: ssi, frequency: "yearly",
                                 covers: "current", first_due_on: Date.new(2026, 10, 10), responsible_user: michael)
  end
  let!(:deadline) do
    obligation.compliance_deadlines.create!(period_start: Date.new(2026, 1, 1), due_on: Date.new(2026, 10, 10))
  end

  def remind(on)
    described_class.new(on: on).run!
  end

  it "ne dit rien plus de quatorze jours avant" do
    expect(remind(Date.new(2026, 9, 20))).to eq(0)
    expect(Notification.count).to eq(0)
  end

  it "rappelle à J-14, une seule fois, avec un lien vers l'échéance" do
    expect(remind(Date.new(2026, 9, 26))).to eq(1)
    expect(remind(Date.new(2026, 9, 27))).to eq(0)

    notification = Notification.sole
    expect(notification.recipient).to eq(michael)
    expect(notification.title).to include("Dans 14 j", "Assurance incendie — 2026", "Société simple de test")
    expect(notification.url).to end_with("/finance/deadlines/#{deadline.id}")
  end

  it "rappelle de nouveau à J-3, puis en retard chaque semaine" do
    remind(Date.new(2026, 9, 26))
    remind(Date.new(2026, 10, 7))
    remind(Date.new(2026, 10, 11))
    remind(Date.new(2026, 10, 14))
    remind(Date.new(2026, 10, 18))

    expect(Notification.order(:id).pluck(:title).map { |title| title.split(" :").first })
      .to eq(["Dans 14 j", "Dans 3 j", "En retard de 1 j", "En retard de 8 j"])
  end

  it "ne rappelle plus une échéance close" do
    deadline.close!(status: "done", user: michael)

    expect(remind(Date.new(2026, 10, 9))).to eq(0)
  end
end
