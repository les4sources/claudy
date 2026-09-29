require "rails_helper"

# Voir, sans accès aux logs de production, si une publication a bien relancé
# le site — et en demander une à la main.
RSpec.describe "API v1 — reconstructions du site", type: :request, queue_adapter: :test do
  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  around do |example|
    previous = ENV.slice("AGENT_API_TOKEN", "WEBSITE_REBUILD_WEBHOOK_URL")
    ENV["AGENT_API_TOKEN"] = token
    ENV["WEBSITE_REBUILD_WEBHOOK_URL"] = "https://deploy.example.org/hook"
    example.run
  ensure
    %w[AGENT_API_TOKEN WEBSITE_REBUILD_WEBHOOK_URL].each { |k| previous.key?(k) ? ENV[k] = previous[k] : ENV.delete(k) }
  end

  def body = JSON.parse(response.body)

  it "refuse sans jeton" do
    get "/api/v1/website_rebuilds"
    expect(response).to have_http_status(:unauthorized)
  end

  it "liste les dernières demandes et dit si le webhook est configuré, sans son URL" do
    WebsiteRebuild.create!(status: "sent", requested_at: 1.hour.ago, last_requested_at: 1.hour.ago, response_code: "200")

    get "/api/v1/website_rebuilds", headers: headers

    expect(response).to have_http_status(:ok)
    expect(body["data"].first).to include("status" => "sent", "response_code" => "200")
    expect(body["meta"]).to include("webhook_configured" => true, "window_seconds" => 120)
    expect(response.body).not_to include("deploy.example.org")
  end

  it "demande une reconstruction immédiate" do
    post "/api/v1/website_rebuilds", headers: headers

    expect(response).to have_http_status(:accepted)
    expect(body["data"]).to include("status" => "pending", "trigger" => "api")
    expect(WebsiteRebuildJob).to have_been_enqueued.once
  end

  it "une publication ouvre une demande" do
    category = EventCategory.create!(name: "Parties")
    starts = Time.zone.parse("2026-11-06 20:00")
    Event.create!(name: "Projection", event_category: category, starts_at: starts, ends_at: starts,
                  slug: "projection", published_at: Time.current)

    get "/api/v1/website_rebuilds", headers: headers
    expect(body["data"].first).to include("status" => "pending", "trigger" => "publication")
  end
end
