require "rails_helper"

RSpec.describe FunnelTimelineHelper, type: :helper do
  let(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:chevetche) { Lodging.create!(name: "La Chevêche", price_night_cents: 30_000) }
  let(:arrival) { Date.new(2027, 1, 22) }

  def draft(**attrs)
    Reservations::Draft.new({ arrival_date: arrival.iso8601, departure_date: (arrival + 2).iso8601 }.merge(attrs))
  end

  it "ne rend rien sans dates ni prestation" do
    expect(helper.reservation_timeline(draft(arrival_date: nil))).to be_nil
    expect(helper.reservation_timeline(draft)).to be_nil
  end

  it "place la nuit J du soir du jour J au matin du jour J+1" do
    expect(helper.timeline_night_columns(0)).to eq([2, 4])
    expect(helper.timeline_night_columns(1)).to eq([4, 6])
  end

  it "fusionne les nuits consécutives d'un même gîte et sépare les autres" do
    timeline = helper.reservation_timeline(draft(lodging_night_ids: [hulotte.id.to_s, chevetche.id.to_s]))

    expect(timeline.days.size).to eq(3)
    segments = timeline.rows.first.segments
    expect(segments.map { |s| [s.text, s.from, s.to] }).to eq([["La Hulotte", 2, 4], ["La Chevêche", 4, 6]])
  end

  it "pose une salle sur la journée, la soirée ou les deux, avec ses pictogrammes" do
    timeline = helper.reservation_timeline(draft(space_slots: { "grande_salle" => %w[journee_et_soiree soiree journee] }))

    row = timeline.rows.first
    expect(row.label).to eq("Grande Salle")
    expect(row.segments.map { |s| [s.text, s.from, s.to, s.icons] }).to eq([
      ["Journée + soirée", 1, 3, %i[sun moon]],
      ["Soirée", 4, 5, %i[moon]],
      ["Journée", 5, 6, %i[sun]]
    ])
  end

  it "compte le camping et les vans nuit par nuit" do
    timeline = helper.reservation_timeline(draft(per_night_resources: { "tente" => %w[4 0], "van" => %w[1 1] }))

    expect(timeline.rows.map { |r| [r.label, r.segments.map { |s| [s.text, s.from, s.to] }] }).to eq([
      ["Camping", [["4 pers.", 2, 4]]],
      ["Van", [["1 van", 2, 6]]]
    ])
  end
end
