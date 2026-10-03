require "rails_helper"

RSpec.describe FunnelDatesHelper, type: :helper do
  it "n'écrit l'année qu'une fois dans la même année" do
    expect(helper.stay_dates_label(Date.new(2026, 10, 24), Date.new(2026, 10, 25)))
      .to eq("24 octobre → 25 octobre 2026")
  end

  it "garde les deux années à cheval sur le Nouvel An" do
    expect(helper.stay_dates_label(Date.new(2026, 12, 30), Date.new(2027, 1, 2)))
      .to eq("30 décembre 2026 → 2 janvier 2027")
  end
end
