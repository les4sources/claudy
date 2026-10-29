require "rails_helper"

# Vidéo publique d'un événement : saisie dans le formulaire, affichée sur la fiche.
RSpec.describe "Événements — vidéo", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "editrice@les4sources.be", password: "password123") }
  let!(:category) { EventCategory.create!(name: "Projections", color: "teal") }
  let!(:event) do
    Event.create!(name: "Projection : Winter Taïga", event_category: category,
                  starts_at: Time.zone.parse("2026-11-06 20:00"), ends_at: Time.zone.parse("2026-11-06 22:00"))
  end

  before { sign_in user }

  def update_with(video_url)
    patch event_path(event), params: {
      event: {
        name: event.name, event_category_id: category.id, video_url: video_url,
        starts_at_date: "2026-11-06", starts_at_time: "20:00", ends_at_date: "2026-11-06", ends_at_time: "22:00"
      }
    }
  end

  it "propose le champ dans le formulaire" do
    get edit_event_path(event)
    expect(response.body).to include("Vidéo (lien YouTube)")
  end

  it "enregistre un lien YouTube et l'affiche sur la fiche" do
    update_with("https://www.youtube.com/watch?v=JbHeySEwIvg")

    expect(event.reload.video_url).to eq("https://www.youtube.com/watch?v=JbHeySEwIvg")
    get event_path(event)
    expect(response.body).to include("https://www.youtube.com/watch?v=JbHeySEwIvg")
  end

  it "refuse un lien qui n'est pas YouTube" do
    update_with("https://wintertaiga.com/")

    expect(event.reload.video_url).to be_nil
    expect(response.body).to include("doit être un lien YouTube")
  end
end
