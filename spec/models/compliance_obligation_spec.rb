require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# L'échéancier comptable — la règle et son calendrier théorique.
RSpec.describe ComplianceObligation do
  include FinanceBuilders

  let(:srl) { build_legal_entity(name: "SRL de test", form: "srl") }

  def obligation(**attrs)
    described_class.create!({ title: "Déclaration TVA", legal_entity: srl, frequency: "quarterly",
                              first_due_on: Date.new(2026, 4, 20), covers: "previous" }.merge(attrs))
  end

  describe "#schedule_through" do
    it "déduit les trimestres de la première échéance, chacun couvrant le trimestre précédent" do
      schedule = obligation.schedule_through(Date.new(2027, 1, 31))

      expect(schedule).to eq([
        [Date.new(2026, 1, 1), Date.new(2026, 4, 20)],
        [Date.new(2026, 4, 1), Date.new(2026, 7, 20)],
        [Date.new(2026, 7, 1), Date.new(2026, 10, 20)],
        [Date.new(2026, 10, 1), Date.new(2027, 1, 20)]
      ])
    end

    it "libelle chaque trimestre par la période couverte, pas par le mois du dépôt" do
      rule = obligation
      labels = rule.schedule_through(Date.new(2026, 12, 31)).map { |(start, _)| rule.period_label(start) }

      expect(labels).to eq(["T1 2026", "T2 2026", "T3 2026"])
    end

    it "fait couvrir l'année EN COURS au précompte immobilier d'octobre" do
      rule = obligation(title: "Précompte immobilier", frequency: "yearly", covers: "current",
                        first_due_on: Date.new(2026, 10, 12))

      schedule = rule.schedule_through(Date.new(2027, 12, 31))
      expect(schedule.map { |(start, _)| rule.period_label(start) }).to eq(%w[2026 2027])
      expect(schedule.map(&:last)).to eq([Date.new(2026, 10, 12), Date.new(2027, 10, 12)])
    end

    # Un 31 janvier qui dériverait en 28 février puis en 28 pour toujours ferait
    # mentir toutes les échéances suivantes.
    it "ne laisse pas dériver un 31 : chaque échéance se calcule depuis la première" do
      rule = obligation(frequency: "monthly", first_due_on: Date.new(2026, 1, 31))

      expect(rule.schedule_through(Date.new(2026, 3, 31)).map(&:last))
        .to eq([Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31)])
    end

    it "s'arrête à la date de fin" do
      rule = obligation(ends_on: Date.new(2026, 8, 1))

      expect(rule.schedule_through(Date.new(2027, 12, 31)).size).to eq(2)
    end

    it "ne produit qu'une échéance pour une obligation ponctuelle, sans période" do
      rule = obligation(title: "Facturation électronique", frequency: "once", first_due_on: Date.new(2026, 1, 1))

      expect(rule.schedule_through(Date.new(2027, 1, 1))).to eq([[Date.new(2026, 1, 1), Date.new(2026, 1, 1)]])
      expect(rule.period_label(Date.new(2026, 1, 1))).to be_nil
    end
  end

  it "refuse deux obligations du même nom pour la même entité" do
    obligation
    doublon = described_class.new(title: "Déclaration TVA", legal_entity: srl, frequency: "yearly",
                                  first_due_on: Date.new(2026, 1, 1))

    expect(doublon).not_to be_valid
  end

  describe "#reminder_recipients" do
    it "rappelle le responsable quand il y en a un" do
      user = User.create!(email: "michael-oblig@les4sources.be", password: "password123")

      expect(obligation(responsible_user: user).reminder_recipients).to eq([user])
    end

    it "se replie sur les destinataires comptables des réglages" do
      compta = User.create!(email: "compta-oblig@les4sources.be", password: "password123")
      Setting.set(NotificationSettingsController::ACCOUNTING_EMAILS_KEY, compta.email)

      expect(obligation.reminder_recipients).to eq([compta])
    end
  end
end
