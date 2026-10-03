require "rails_helper"

# Statistiques du site (2026-10-03) — visites des fiches événement et activité :
# classement dans Reporting › Site web et encart « Site web » de chaque fiche.
RSpec.describe "Statistiques du site — événements et activités", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "fiches-stats@les4sources.be", password: "password123") }
  let!(:category) { EventCategory.create!(name: "Parties", color: "amber") }
  let!(:event) do
    Event.create!(name: "Pizza party d'octobre", event_category: category,
                  starts_at: 1.week.from_now, ends_at: 1.week.from_now + 3.hours,
                  published_at: 1.day.ago, slug: "pizza-party-octobre-2026")
  end
  let!(:experience) { Experience.create!(name: "Grimpe dans les arbres", published_at: 1.day.ago, slug: "grimpe-dans-les-arbres") }

  def hit(visitor, path, kind: "pageview", name: nil)
    SiteHit.create!(visitor_hash: visitor, path: path, kind: kind, name: name,
                    occurred_at: Time.current, day: Time.zone.today)
  end

  before do
    sign_in user
    hit("a", "/evenements/pizza-party-octobre-2026")
    hit("a", "/evenements/pizza-party-octobre-2026")
    hit("a", "/evenements/pizza-party-octobre-2026", kind: "event", name: "tally")
    hit("a", "/evenements/pizza-party-octobre-2026", kind: "event", name: "tally_submit")
    hit("b", "/evenements/pizza-party-octobre-2026")
    hit("b", "/evenements/stage-ete-2025")
    hit("c", "/catalogue/grimpe-dans-les-arbres")
    hit("c", "/agenda")
  end

  it "classe les fiches avec le nom de leur fiche Claudy, visites, vues, clics et formulaires" do
    report = SiteStats::Report.new(period: "7")

    expect(report.event_pages.first).to include(label: "Pizza party d'octobre", record: event, visits: 2, pageviews: 3,
                                                clicks: 1, submissions: 1)
    expect(report.event_pages.map { |row| row[:label] }).to eq(["Pizza party d'octobre", "Stage ete 2025"])
    expect(report.experience_pages).to contain_exactly(include(label: "Grimpe dans les arbres", visits: 1, pageviews: 1))
  end

  it "affiche les deux classements sur le tableau de bord" do
    get site_stats_path(period: "7")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pizza party d&#39;octobre", "Grimpe dans les arbres", event_path(event))
  end

  it "montre les visites de la fiche sur la page de l'événement et de l'activité" do
    get event_path(event)
    expect(response.body).to include("2 visites", "de la fiche ces 30 derniers jours", "1 clic d&#39;inscription ou de contact",
                                     "1 formulaire envoyé")

    get experience_path(experience)
    expect(response.body).to include("1 visite", "de la fiche ces 30 derniers jours")
  end
end
