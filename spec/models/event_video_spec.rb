require "rails_helper"

# Vidéo publique d'un événement (`video_url`) : un lien YouTube que le site
# affiche sur la fiche.
RSpec.describe Event, type: :model do
  let!(:category) { EventCategory.create!(name: "Projections", color: "teal") }
  let(:starts_at) { Time.zone.parse("2026-11-06 20:00") }

  def build_event(**attributes)
    Event.new(name: "Projection : Winter Taïga", event_category: category,
              starts_at: starts_at, ends_at: starts_at + 2.hours, **attributes)
  end

  it "est facultative" do
    expect(build_event).to be_valid
    expect(build_event(video_url: "  ").tap(&:valid?).video_url).to be_nil
  end

  {
    "https://www.youtube.com/watch?v=JbHeySEwIvg" => "JbHeySEwIvg",
    "https://youtube.com/watch?si=abc&v=JbHeySEwIvg&t=12s" => "JbHeySEwIvg",
    "https://m.youtube.com/watch?v=JbHeySEwIvg" => "JbHeySEwIvg",
    "https://youtu.be/JbHeySEwIvg?si=xyz" => "JbHeySEwIvg",
    "https://www.youtube.com/shorts/JbHeySEwIvg" => "JbHeySEwIvg",
    "https://www.youtube.com/embed/JbHeySEwIvg" => "JbHeySEwIvg",
    " https://www.youtube.com/watch?v=JbHeySEwIvg " => "JbHeySEwIvg"
  }.each do |url, id|
    it "accepte #{url.strip} et en tire l'identifiant" do
      event = build_event(video_url: url)
      expect(event).to be_valid
      expect(event.video_url).to eq(url.strip)
      expect(event.youtube_video_id).to eq(id)
    end
  end

  [
    "https://wintertaiga.com/",
    "https://vimeo.com/123456789",
    "https://www.youtube.com/@les4sources",
    "https://www.youtube.com/watch?v=trop-court",
    "javascript:alert(1)"
  ].each do |url|
    it "refuse #{url}" do
      event = build_event(video_url: url)
      expect(event).not_to be_valid
      expect(event.errors[:video_url]).to be_present
    end
  end
end
