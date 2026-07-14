require "rails_helper"

# Epic #25, Phase 5 — calendrier hebdo de TOUTES les activités.
RSpec.describe Experiences::GlobalWeekCalendar do
  let(:monday) { Date.today.beginning_of_week(:monday) }
  let(:balade) { Experience.create!(name: "Balade avec les ânes", duration_hours: 2) }
  let(:poterie) { Experience.create!(name: "Atelier poterie", duration_hours: 3) }

  def availability(experience, day, starts_at)
    ExperienceAvailability.create!(experience: experience, available_on: day, starts_at: starts_at)
  end

  describe "cadrage de la semaine" do
    it "démarre sur la semaine en cours par défaut" do
      calendar = described_class.new

      expect(calendar.week_start).to eq(monday)
      expect(calendar).to be_current_week
      expect(calendar.days.size).to eq(7)
      expect(calendar.days.first).to eq(monday)
      expect(calendar.days.last).to eq(monday + 6)
    end

    it "se cale sur le lundi de la semaine demandée" do
      calendar = described_class.new(week_start: monday + 9) # un mercredi

      expect(calendar.week_start).to eq(monday + 7)
      expect(calendar).not_to be_current_week
    end

    it "navigue d'une semaine à l'autre" do
      calendar = described_class.new(week_start: monday)

      expect(calendar.previous_week).to eq(monday - 7)
      expect(calendar.next_week).to eq(monday + 7)
    end

    it "expose les lignes horaires de 8h à 21h (22h = fermeture)" do
      expect(described_class.new.hours).to eq((8..21).to_a)
    end
  end

  describe "agrégation des créneaux" do
    it "ne retient que les créneaux de la semaine affichée" do
      dans_la_semaine = availability(balade, monday + 1, "10:00")
      availability(balade, monday + 10, "10:00") # semaine suivante

      calendar = described_class.new(week_start: monday)

      expect(calendar.availabilities).to eq([dans_la_semaine])
    end

    it "range chaque créneau dans la ligne de son heure de début" do
      matin = availability(balade, monday + 1, "10:00")
      apres_midi = availability(balade, monday + 1, "14:00")

      calendar = described_class.new(week_start: monday)

      expect(calendar.availabilities_at(monday + 1, 10)).to eq([matin])
      expect(calendar.availabilities_at(monday + 1, 14)).to eq([apres_midi])
      expect(calendar.availabilities_at(monday + 1, 9)).to be_empty
    end

    it "range un créneau de 21h30 dans la ligne de 21h" do
      tardif = Experience.create!(name: "Observation des étoiles", duration_hours: 0.5)
      bloc = availability(tardif, monday + 2, "21:30")

      calendar = described_class.new(week_start: monday)

      expect(calendar.availabilities_at(monday + 2, 21)).to eq([bloc])
    end

    it "empile les créneaux de DEUX activités qui se chevauchent (c'est voulu)" do
      a = availability(balade, monday + 3, "10:00")
      b = availability(poterie, monday + 3, "10:00")

      calendar = described_class.new(week_start: monday)
      slots = calendar.availabilities_at(monday + 3, 10)

      expect(slots).to contain_exactly(a, b)
      # ordre stable : à heure égale, alphabétique par activité
      expect(slots.map { |s| s.experience.name }).to eq(["Atelier poterie", "Balade avec les ânes"])
    end
  end

  describe "légende" do
    it "liste les activités présentes dans la semaine, sans doublon, par ordre alphabétique" do
      availability(poterie, monday + 1, "09:00")
      availability(balade, monday + 2, "09:00")
      availability(balade, monday + 3, "09:00")

      calendar = described_class.new(week_start: monday)

      expect(calendar.experiences.map(&:name)).to eq(["Atelier poterie", "Balade avec les ânes"])
    end

    it "est vide quand aucun créneau n'est posé" do
      calendar = described_class.new(week_start: monday)

      expect(calendar).not_to be_any
      expect(calendar.experiences).to be_empty
    end
  end
end
