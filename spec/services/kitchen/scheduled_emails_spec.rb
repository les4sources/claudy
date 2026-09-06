require "rails_helper"

# Les deux envois planifiés de la cuisine (epic #219, phase 7).
RSpec.describe "Cuisine — envois planifiés" do
  let(:customer) { Customer.create!(email: "client-cron@example.com", first_name: "Groupe", last_name: "Cron") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let!(:michael) { Human.create!(name: "Michael", email: "michael@les4sources.be", status: "active") }

  before { ActionMailer::Base.deliveries.clear }

  def line(**attrs)
    order = MealOrder.new({ stay: stay, kind: "repas", people: 10, date: Date.current + 3,
                            responsible_human: steph }.merge(attrs))
    order.skip_notifications = true
    order.tap(&:save!)
  end

  describe Kitchen::WeeklyDigest do
    it "envoie un email par personne, avec ses lignes seulement" do
      line
      line(responsible_human: michael, date: Date.current + 5)

      described_class.new.run

      expect(ActionMailer::Base.deliveries.map { |m| m.to.first })
        .to match_array(%w[steph@les4sources.be michael@les4sources.be])
      steph_mail = ActionMailer::Base.deliveries.find { |m| m.to == ["steph@les4sources.be"] }
      expect(steph_mail.subject).to eq("Cuisine — les 14 prochains jours")
    end

    it "revient au responsable par défaut pour une ligne que personne ne porte" do
      Setting.set("kitchen.buffet.default_human_id", michael.id)
      line(kind: "buffet_vege", responsible_human: nil)

      described_class.new.run

      expect(ActionMailer::Base.deliveries.map { |m| m.to.first }).to eq(["michael@les4sources.be"])
    end

    it "ignore ce qui est hors horizon, annulé ou refusé" do
      line(date: Date.current + 30)
      line(date: Date.current + 2, status: "cancelled", cancellation_reason: "annulé")
      line(date: Date.current + 2, validation: "refused", refusal_reason: "indisponible")

      expect(described_class.new.run).to include("aucune prestation")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "ne renvoie pas deux fois dans la même semaine, sauf FORCE" do
      line
      described_class.new.run
      ActionMailer::Base.deliveries.clear

      expect(described_class.new.run).to include("déjà envoyé")
      expect(ActionMailer::Base.deliveries).to be_empty

      described_class.new(force: true).run
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end
  end

  describe Kitchen::BreadReminders do
    it "rappelle exactement à J-5, et une seule fois" do
      order = line(date: Date.current + 5, status: "confirmed", validation: "accepted")

      described_class.new.run

      expect(ActionMailer::Base.deliveries.last.subject).to include("Pain à commander")
      expect(order.reload.bread_reminder_sent_at).to be_present

      ActionMailer::Base.deliveries.clear
      expect(described_class.new.run).to include("aucune prestation")
    end

    it "laisse tranquille ce qui n'est ni à J-5 ni accepté" do
      line(date: Date.current + 4, validation: "accepted", status: "confirmed")
      line(date: Date.current + 5, validation: "pending", status: "confirmed")
      line(date: Date.current + 5, validation: "accepted", status: "inquiry")

      described_class.new.run

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "garde éligible une ligne dont le responsable n'a pas d'email" do
      sans_email = Human.create!(name: "Sans email", status: "active")
      order = line(date: Date.current + 5, status: "confirmed", validation: "accepted",
                   responsible_human: sans_email)

      described_class.new.run

      expect(ActionMailer::Base.deliveries).to be_empty
      expect(order.reload.bread_reminder_sent_at).to be_nil
    end
  end
end
