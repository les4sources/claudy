require "rails_helper"

# Publication d'une activité sur le site (concern `Publishable`).
RSpec.describe Experience, type: :model do
  it "propose un slug depuis le libellé, le pose à la publication et le fige ensuite" do
    experience = Experience.create!(name: "Grimpe encadrée dans les arbres")
    expect(experience.slug).to be_nil
    expect(experience.suggested_slug).to eq("grimpe-encadree-dans-les-arbres")
    expect(experience.public_path).to be_nil

    experience.update!(published_at: Time.current)
    expect(experience.slug).to eq("grimpe-encadree-dans-les-arbres")
    expect(experience.public_path).to eq("/catalogue/grimpe-encadree-dans-les-arbres")

    experience.slug = "grimpe"
    expect(experience).not_to be_valid
  end

  it "formate la durée publique depuis le libellé ou la durée numérique" do
    expect(Experience.new(name: "A", duration: "une demi-journée", duration_hours: 3).public_duration_text).to eq("une demi-journée")
    expect(Experience.new(name: "B", duration_hours: 2.5).public_duration_text).to eq("2,5 h")
    expect(Experience.new(name: "C", duration_hours: 2).public_duration_text).to eq("2 h")
    expect(Experience.new(name: "D").public_duration_text).to be_nil
  end

  it "demande une reconstruction du site quand une activité publiée change" do
    experience = Experience.create!(name: "Bain d'ânes")
    expect(WebsiteRebuildJob).to receive(:request!).twice
    experience.update!(published_at: Time.current)
    experience.update!(summary: "Un moment apaisant")
  end
end
