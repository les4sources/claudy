require "rails_helper"

# Ligne de garde — qui décroche à un instant donné.
RSpec.describe OnCall::Resolver do
  let!(:role) { Role.find_or_create_by!(id: described_class::WATCHMAN_ROLE_ID) { |r| r.name = "Veilleur·euse" } }

  let(:ana) { Human.create!(name: "Ana", phone: "0470 11 11 11") }
  let(:bob) { Human.create!(name: "Bob", phone: "0470 22 22 22") }
  let(:cleo) { Human.create!(name: "Cléo", phone: "0470 33 33 33") }

  def garde(human, date, status: :selected)
    HumanRole.create!(human: human, role: role, date: date, status: status)
  end

  describe ".duty_date_for — bascule à l'heure configurée" do
    it "garde la veille avant l'heure de bascule, le jour même à partir d'elle" do
      before_handover = Time.find_zone("Europe/Brussels").local(2026, 9, 28, 6, 59)
      at_handover = Time.find_zone("Europe/Brussels").local(2026, 9, 28, 7, 0)

      expect(described_class.duty_date_for(before_handover, 7)).to eq(Date.new(2026, 9, 27))
      expect(described_class.duty_date_for(at_handover, 7)).to eq(Date.new(2026, 9, 28))
    end

    it "ne bascule pas à minuit" do
      midnight = Time.find_zone("Europe/Brussels").local(2026, 9, 28, 0, 30)
      expect(described_class.duty_date_for(midnight, 7)).to eq(Date.new(2026, 9, 27))
    end

    it "lit l'heure de bascule dans les paramètres" do
      Setting.set(OnCall::Config::HANDOVER_HOUR_KEY, 9)
      at = Time.find_zone("Europe/Brussels").local(2026, 9, 28, 8, 30)

      expect(described_class.new(at: at).duty_date).to eq(Date.new(2026, 9, 27))
    end

    it "vaut 7 h par défaut" do
      expect(OnCall::Config.handover_hour).to eq(7)
    end

    # Passage à l'heure d'été le 29 mars 2026 : 7 h locale = 5 h UTC (et non 6 h).
    it "suit l'heure d'été (passage de mars)" do
      expect(described_class.duty_date_for(Time.utc(2026, 3, 29, 4, 59), 7)).to eq(Date.new(2026, 3, 28))
      expect(described_class.duty_date_for(Time.utc(2026, 3, 29, 5, 0), 7)).to eq(Date.new(2026, 3, 29))
    end

    # Retour à l'heure d'hiver le 25 octobre 2026 : 7 h locale = 6 h UTC.
    it "suit l'heure d'hiver (passage d'octobre)" do
      expect(described_class.duty_date_for(Time.utc(2026, 10, 25, 5, 59), 7)).to eq(Date.new(2026, 10, 24))
      expect(described_class.duty_date_for(Time.utc(2026, 10, 25, 6, 0), 7)).to eq(Date.new(2026, 10, 25))
    end
  end

  describe "#on_call" do
    let(:date) { Date.new(2026, 9, 28) }
    subject(:resolver) { described_class.new(duty_date: date) }

    it "renvoie nil sur un planning vide" do
      expect(resolver.on_call).to be_nil
      expect(resolver.backup).to be_nil
    end

    it "renvoie le seul titulaire" do
      garde(ana, date)
      expect(resolver.on_call).to eq(ana)
    end

    it "ignore les gardes d'un autre jour et les suppléants" do
      garde(ana, date - 1)
      garde(bob, date, status: :backup)
      expect(resolver.on_call).to be_nil
      expect(resolver.backup).to eq(bob)
    end

    it "prend le premier titulaire inscrit quand personne n'est désigné" do
      garde(bob, date)
      garde(ana, date)
      expect(resolver.on_call).to eq(bob)
    end

    it "prend le veilleur qui tient le téléphone" do
      garde(bob, date)
      garde(ana, date).make_phone_holder!
      expect(resolver.on_call).to eq(ana)
    end

    it "passe au titulaire suivant si le porteur n'a pas de numéro" do
      ana.update!(phone: nil)
      garde(bob, date)
      garde(ana, date).make_phone_holder!
      expect(resolver.on_call).to eq(bob)
    end

    it "n'appelle pas un membre désactivé" do
      garde(cleo, date)
      cleo.update!(status: "inactive")
      expect(resolver.on_call).to be_nil
    end
  end

  describe "HumanRole#make_phone_holder!" do
    it "retire le téléphone aux autres veilleurs du jour" do
      date = Date.new(2026, 9, 28)
      first = garde(ana, date)
      second = garde(bob, date)
      first.make_phone_holder!
      second.make_phone_holder!

      expect(first.reload.phone_holder).to be(false)
      expect(second.reload.phone_holder).to be(true)
    end
  end
end
