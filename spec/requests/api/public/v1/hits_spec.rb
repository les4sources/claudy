require "rails_helper"

# Statistiques du site sans cookie (2026-10-03) — le point d'entrée des pages
# vues et événements envoyés par www.les4sources.be.
RSpec.describe "Api::Public::V1::Hits", type: :request do
  include Devise::Test::IntegrationHelpers

  HITS_SITE = "https://www.les4sources.be".freeze
  HITS_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze

  def beacon(payload = {}, origin: HITS_SITE, user_agent: HITS_UA, ip: "203.0.113.7", country: "BE", remote_addr: "172.64.0.10", **fields)
    post "/api/public/v1/hits",
         params: payload.merge(fields).to_json,
         headers: { "Content-Type" => "text/plain;charset=UTF-8", "Origin" => origin,
                    "User-Agent" => user_agent, "CF-Connecting-IP" => ip, "CF-IPCountry" => country,
                    "REMOTE_ADDR" => remote_addr }
  end

  it "enregistre une page vue avec sa source, sa campagne, son appareil et son pays" do
    beacon(k: "pageview", u: "#{HITS_SITE}/sejours/tarifs/?utm_source=Newsletter&utm_campaign=automne", r: "https://www.google.com/")

    expect(response).to have_http_status(:no_content)
    hit = SiteHit.last
    expect(hit).to have_attributes(kind: "pageview", path: "/sejours/tarifs", source: "Google",
                                   referrer_host: "google.com", utm_source: "newsletter", utm_campaign: "automne",
                                   device: "Mobile", browser: "Safari", os: "iOS", country: "BE", day: Time.zone.today)
    expect(hit.visitor_hash).to match(/\A\h{64}\z/)
  end

  it "ne pose aucun cookie et ne garde ni IP ni User-Agent" do
    beacon(k: "pageview", u: "#{HITS_SITE}/")

    expect(response.headers["Set-Cookie"]).to be_blank
    expect(SiteHit.column_names.grep(/ip|agent/)).to be_empty
    expect(SiteHit.last.attributes.values.compact.map(&:to_s)).not_to include("203.0.113.7")
  end

  it "donne la même empreinte au même visiteur dans la journée, une autre à un autre visiteur" do
    beacon(k: "pageview", u: "#{HITS_SITE}/")
    beacon(k: "pageview", u: "#{HITS_SITE}/agenda", r: "#{HITS_SITE}/")
    beacon(k: "pageview", u: "#{HITS_SITE}/", ip: "198.51.100.9")

    first, second, other = SiteHit.order(:id).to_a
    expect(second.visitor_hash).to eq(first.visitor_hash)
    expect(other.visitor_hash).not_to eq(first.visitor_hash)
    expect(first.source).to eq("Accès direct")
    expect(second.source).to be_nil
  end

  it "supprime le sel des jours passés au premier passage du jour" do
    SiteVisitSalt.create!(day: Time.zone.today - 1, salt: "hier")

    beacon(k: "pageview", u: "#{HITS_SITE}/")

    expect(SiteVisitSalt.pluck(:day)).to eq([Time.zone.today])
  end

  it "enregistre un clic sortant sans les paramètres de la destination" do
    beacon(k: "event", n: "reservation", u: "#{HITS_SITE}/sejours", t: "https://app.les4sources.be/reservation?x=1")

    expect(SiteHit.last).to have_attributes(kind: "event", name: "reservation", path: "/sejours",
                                            target: "https://app.les4sources.be/reservation")
  end

  it "ignore les robots" do
    beacon({ k: "pageview", u: "#{HITS_SITE}/" }, user_agent: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")

    expect(response).to have_http_status(:no_content)
    expect(SiteHit.count).to eq(0)
  end

  it "ignore un membre connecté à Claudy, sans lui renvoyer de cookie" do
    user = User.create!(email: "membre-stats@les4sources.be", password: "password123")
    sign_in user
    get root_path

    beacon(k: "pageview", u: "#{HITS_SITE}/")

    expect(response).to have_http_status(:no_content)
    expect(response.headers["Set-Cookie"]).to be_blank
    expect(SiteHit.count).to eq(0)
  end

  it "refuse une autre origine que le site" do
    beacon({ k: "pageview", u: "https://ailleurs.example/" }, origin: "https://ailleurs.example")

    expect(response).to have_http_status(:forbidden)
    expect(SiteHit.count).to eq(0)
  end

  it "refuse un corps illisible et ignore un événement inconnu" do
    post "/api/public/v1/hits", params: "pas du json",
                                headers: { "Content-Type" => "text/plain", "Origin" => HITS_SITE, "User-Agent" => HITS_UA }
    expect(response).to have_http_status(:forbidden).or have_http_status(:bad_request)

    beacon(k: "event", n: "inconnu", u: "#{HITS_SITE}/")
    expect(response).to have_http_status(:no_content)
    expect(SiteHit.count).to eq(0)
  end

  it "refuse les étapes du funnel, qui ne s'écrivent que côté serveur" do
    beacon(k: "event", n: "funnel_request", u: "#{HITS_SITE}/")

    expect(response).to have_http_status(:no_content)
    expect(SiteHit.count).to eq(0)
  end

  it "refuse un octet nul et un corps trop gros, sans erreur serveur" do
    beacon(k: "pageview", u: "#{HITS_SITE}/", t: "a\u0000b")
    expect(response).to have_http_status(:bad_request)

    beacon(k: "pageview", u: "#{HITS_SITE}/", r: "x" * 5_000)
    expect(response).to have_http_status(:content_too_large)
    expect(SiteHit.count).to eq(0)
  end

  it "ne croit CF-Connecting-IP que s'il vient d'un relais Cloudflare" do
    beacon({ k: "pageview", u: "#{HITS_SITE}/" }, ip: "198.51.100.1", remote_addr: "192.0.2.50")
    beacon({ k: "pageview", u: "#{HITS_SITE}/" }, ip: "198.51.100.2", remote_addr: "192.0.2.50")

    expect(SiteHit.distinct.count(:visitor_hash)).to eq(1)
  end
end
