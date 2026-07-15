require "rails_helper"

# Epic #25, Phase 5 — une couleur par activité, attribuée à la création.
RSpec.describe Experience, "couleur" do
  it "attribue une couleur de la palette à la création" do
    experience = Experience.create!(name: "Balade avec les ânes")

    expect(experience.color).to be_present
    expect(Experience::PALETTE).to include(experience.color)
  end

  it "ne donne pas la même couleur à deux activités créées à la suite" do
    couleurs = 3.times.map { |i| Experience.create!(name: "Activité #{i}").color }

    expect(couleurs.uniq.size).to eq(3)
  end

  it "répartit la palette avant de réutiliser une couleur" do
    Experience::PALETTE.size.times { |i| Experience.create!(name: "Activité #{i}") }
    couleurs = Experience.unscoped.pluck(:color)

    expect(couleurs.sort).to eq(Experience::PALETTE.sort)
  end

  it "respecte une couleur fournie explicitement" do
    experience = Experience.create!(name: "Poterie", color: "#123abc")

    expect(experience.color).to eq("#123abc")
  end

  it "refuse une couleur qui n'est pas un hexadécimal à 6 chiffres" do
    experience = Experience.new(name: "Poterie", color: "vert")

    expect(experience).not_to be_valid
    expect(experience.errors[:color]).to be_present
  end

  describe "décorateur" do
    it "rend un style inline (les classes Tailwind dynamiques seraient purgées)" do
      decorated = ExperienceDecorator.new(Experience.create!(name: "Poterie", color: "#059669"))

      expect(decorated.calendar_chip_style).to include("#059669")
      expect(decorated.legend_dot_style).to eq("background-color: #059669;")
    end

    it "retombe sur une couleur neutre si l'activité n'en a pas" do
      experience = Experience.create!(name: "Poterie")
      experience.update_columns(color: nil)

      expect(ExperienceDecorator.new(experience.reload).color).to eq(ExperienceDecorator::FALLBACK_COLOR)
    end
  end
end
