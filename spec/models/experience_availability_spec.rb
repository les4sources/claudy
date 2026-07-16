require "rails_helper"

# Epic #25, Phase 4 — les blocs de disponibilité ont la durée de l'activité,
# tiennent entre 8h et 22h, et ne se chevauchent jamais.
RSpec.describe ExperienceAvailability, type: :model do
  let(:experience) { Experience.create!(name: "Balade en forêt", duration_hours: 2) }
  let(:day) { Date.today + 7 }

  def availability(starts_at:, on: day, duration: nil)
    ExperienceAvailability.new(experience: experience, available_on: on,
                               starts_at: starts_at, duration_minutes: duration)
  end

  describe "durée par défaut" do
    it "reprend la durée de l'activité quand elle n'est pas précisée" do
      block = availability(starts_at: "09:00")
      expect(block).to be_valid
      expect(block.duration_minutes).to eq(120)
    end

    it "respecte une durée explicitement fournie" do
      block = availability(starts_at: "09:00", duration: 90)
      expect(block).to be_valid
      expect(block.duration_minutes).to eq(90)
    end
  end

  describe "bornes 8h — 22h" do
    it "accepte un bloc qui démarre à 8h" do
      expect(availability(starts_at: "08:00")).to be_valid
    end

    it "accepte un bloc qui finit pile à 22h" do
      expect(availability(starts_at: "20:00")).to be_valid
    end

    it "refuse un bloc qui démarre avant 8h" do
      block = availability(starts_at: "07:00")
      expect(block).not_to be_valid
      expect(block.errors[:starts_at]).to include("doit tenir entre 8h et 22h")
    end

    it "refuse un bloc qui déborde après 22h" do
      block = availability(starts_at: "21:00") # 21h + 2h = 23h
      expect(block).not_to be_valid
      expect(block.errors[:starts_at]).to include("doit tenir entre 8h et 22h")
    end
  end

  describe "non-chevauchement" do
    before { availability(starts_at: "10:00").save! }

    it "refuse un bloc qui démarre pendant un bloc existant" do
      block = availability(starts_at: "11:00")
      expect(block).not_to be_valid
      expect(block.errors[:starts_at]).to include("chevauche une disponibilité déjà posée")
    end

    it "refuse un bloc identique" do
      expect(availability(starts_at: "10:00")).not_to be_valid
    end

    it "refuse un bloc qui englobe un bloc existant" do
      expect(availability(starts_at: "09:00", duration: 240)).not_to be_valid
    end

    it "accepte un bloc contigu (fin = début du suivant)" do
      expect(availability(starts_at: "12:00")).to be_valid
    end

    it "accepte le même horaire un autre jour" do
      expect(availability(starts_at: "10:00", on: day + 1)).to be_valid
    end

    it "accepte le même horaire pour une autre activité" do
      other = Experience.create!(name: "Poterie", duration_hours: 2)
      block = ExperienceAvailability.new(experience: other, available_on: day, starts_at: "10:00")
      expect(block).to be_valid
    end

    it "ne se considère pas comme son propre chevauchement à la mise à jour" do
      block = experience.experience_availabilities.find_by(starts_at: "10:00")
      block.notes = "changé"
      expect(block).to be_valid
    end
  end

  # Epic #55 Phase 6 — les créneaux proposables à l'ajout d'activité sur un séjour
  # ne doivent jamais inclure une activité SUPPRIMÉE : `experience` serait alors
  # `nil` (soft-delete default_scope) et `#label` (→ `experience.name`) planterait
  # le rendu de la modale séjour pour l'admin.
  describe ".for_user" do
    let(:admin) { User.create!(email: "staff@les4sources.be", password: "password123") }
    let!(:avail) do
      ExperienceAvailability.create!(experience: experience, available_on: Date.today + 7, starts_at: "10:00")
    end

    it "propose les créneaux d'une activité vivante à un admin global" do
      expect(described_class.for_user(admin)).to include(avail)
    end

    it "EXCLUT les créneaux d'une activité supprimée (soft-delete) — #label ne plante pas" do
      experience.destroy
      expect(described_class.for_user(admin)).not_to include(avail)
      expect { described_class.for_user(admin).map(&:label) }.not_to raise_error
    end
  end
end
