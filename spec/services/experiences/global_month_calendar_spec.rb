require "rails_helper"

# Calendrier global MENSUEL de /experiences (2026-07-20) : une ligne par
# activité ayant des créneaux dans le mois, un COMPTE par jour (pas le détail).
RSpec.describe Experiences::GlobalMonthCalendar do
  let(:month) { Date.today.next_month.beginning_of_month }

  it "compte les créneaux par activité et par jour, activités triées par nom" do
    zytho = Experience.create!(name: "Zythologie", fixed_price_cents: 12_000, price_cents: 700)
    anes  = Experience.create!(name: "Ânes", fixed_price_cents: 12_000, price_cents: 0)
    2.times { |i| ExperienceAvailability.create!(experience: zytho, available_on: month + 3, starts_at: "#{10 + i}:00") }
    ExperienceAvailability.create!(experience: anes, available_on: month + 5, starts_at: "14:00")
    # Hors mois : ignoré.
    ExperienceAvailability.create!(experience: anes, available_on: month.next_month + 1, starts_at: "14:00")

    calendar = described_class.new(month: month.strftime("%Y-%m"))

    expect(calendar.days.size).to eq(month.end_of_month.day)
    expect(calendar.rows.map { |e, _| e.name }).to eq(["Zythologie", "Ânes"].sort)
    zytho_counts = calendar.rows.find { |e, _| e == zytho }.last
    expect(zytho_counts[month + 3]).to eq(2)
    expect(zytho_counts[month + 5]).to be_nil
  end

  it "sans créneau dans le mois : any? est faux" do
    expect(described_class.new(month: month.strftime("%Y-%m")).any?).to be(false)
  end

  it "tolère un paramètre de mois invalide (repli mois courant)" do
    expect(described_class.new(month: "n'importe quoi").month).to eq(Date.today.beginning_of_month)
  end
end
