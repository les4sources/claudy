require "rails_helper"

# Statistiques du site (2026-10-03) — les étapes du funnel /reservation
# comptent dans l'entonnoir, avec l'empreinte du jour du visiteur.
RSpec.describe "Public::Reservations — statistiques du site", type: :request do
  FUNNEL_STATS_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15".freeze
  let(:headers) { { "User-Agent" => FUNNEL_STATS_UA, "CF-Connecting-IP" => "203.0.113.7" } }

  it "enregistre l'étape des dates puis celle des coordonnées, pour le même visiteur" do
    get "/reservation/sejour", headers: headers
    post "/reservation/sejour", headers: headers, params: {
      reservation: { arrival_date: (Date.today + 40).iso8601, departure_date: (Date.today + 42).iso8601, adults: 2 }
    }
    get "/reservation/coordonnees", headers: headers

    steps = SiteHit.order(:id).pluck(:name, :path, :visitor_hash)
    expect(steps.map(&:first)).to eq(%w[funnel_dates funnel_contact])
    expect(steps.map(&:second)).to eq(%w[/reservation/sejour /reservation/coordonnees])
    expect(steps.map(&:third).uniq.size).to eq(1)
  end

  it "n'enregistre rien pour un robot" do
    get "/reservation/sejour", headers: { "User-Agent" => "Googlebot/2.1" }

    expect(response).to have_http_status(:ok)
    expect(SiteHit.count).to eq(0)
  end
end
