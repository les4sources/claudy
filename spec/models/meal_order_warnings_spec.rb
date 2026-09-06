require "rails_helper"

# Avertissements d'usage et responsable par défaut (epic #219, phase 2).
# Le principe : Claudy DIT quand une demande sort de l'usage, il ne refuse pas.
RSpec.describe "MealOrder — avertissements et responsable par défaut" do
  let(:customer) { Customer.create!(email: "warn@example.com", first_name: "W", last_name: "Arn") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }

  def line(**attrs)
    MealOrder.new({ stay: stay, kind: "repas", people: 10, date: Date.current + 30 }.merge(attrs))
  end

  it "n'avertit de rien dans l'usage courant" do
    expect(line.warnings).to be_empty
  end

  it "avertit au-delà du plafond de convives de la famille" do
    expect(line(people: 30).warnings).to eq(["Au-delà du plafond de 25 convives pour les repas"])
  end

  it "avertit quand la date est plus proche que le délai habituel" do
    expect(line(date: Date.current + 2).warnings)
      .to eq(["Date à moins de 7 jours, délai habituel pour les repas"])
  end

  it "cumule les deux avertissements" do
    expect(line(people: 30, date: Date.current + 2).warnings.size).to eq(2)
  end

  it "se tait quand le plafond a été effacé dans les paramètres" do
    Setting.set("kitchen.repas.max_people", "")

    expect(line(people: 30).warnings).to be_empty
  end

  it "n'avertit pas sur une famille sans plafond ni sur une ligne sans date" do
    expect(line(kind: "buffet_vege", people: 60).warnings).to be_empty
    expect(line(date: nil).warnings).to be_empty
  end

  describe "responsable par défaut" do
    let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be") }

    it "se pose à la création quand personne n'est nommé" do
      Setting.set("kitchen.repas.default_human_id", steph.id)

      expect(line.tap(&:save!).responsible_human).to eq(steph)
    end

    it "ne remplace jamais un responsable choisi" do
      Setting.set("kitchen.repas.default_human_id", steph.id)
      michael = Human.create!(name: "Michael", email: "michael@les4sources.be")

      expect(line(responsible_human: michael).tap(&:save!).responsible_human).to eq(michael)
    end

    it "laisse la ligne sans responsable quand la famille n'en a pas" do
      expect(line(kind: "apero").tap(&:save!).responsible_human).to be_nil
    end
  end
end
