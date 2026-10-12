require "rails_helper"

# Page Cycles (/organisation) : à côté du prochain rassemblement, un accès au
# précédent (Michael, 2026-10-12).
RSpec.describe "Organisation — rassemblement précédent", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "precedent@les4sources.be", password: "password123") }
  let!(:category) { GatheringCategory.create!(name: "Collectif", color: "emerald", default_start_time: "19:30", default_duration_minutes: 120) }

  def gathering(name, days_from_now)
    starts = Time.zone.parse("#{Date.current + days_from_now} 19:30")
    Gathering.create!(gathering_category: category, name: name, starts_at: starts, ends_at: starts + 2.hours)
  end

  before { sign_in user }

  it "lie le dernier rassemblement terminé, pas un plus ancien" do
    older = gathering("Réunion d'avant", -30)
    previous = gathering("Réunion passée", -7)
    upcoming = gathering("Réunion à venir", 7)

    get organisation_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rassemblement précédent")
    expect(response.body).to include(%(href="#{gathering_path(previous)}"))
    expect(response.body).to include(%(href="#{gathering_path(upcoming)}"))
    expect(response.body).not_to include(%(href="#{gathering_path(older)}"))
  end

  it "garde l'accès au précédent quand rien n'est prévu" do
    previous = gathering("Réunion passée", -7)

    get organisation_path

    expect(response.body).to include("Aucun moment à venir")
    expect(response.body).to include(%(href="#{gathering_path(previous)}"))
  end

  it "n'affiche rien de plus sans rassemblement passé" do
    gathering("Réunion à venir", 7)

    get organisation_path

    expect(response.body).not_to include("Rassemblement précédent")
  end
end
