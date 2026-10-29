require "rails_helper"

# Claudy installable (redesign, Michael 2026-10-29) : le manifeste se lit sans
# session, les icônes et la page hors ligne qu'il cite existent, chaque page
# l'annonce, et le service worker ne s'enregistre qu'en production.
RSpec.describe "Claudy installable", type: :request do
  include Devise::Test::IntegrationHelpers

  it "sert le manifeste sans connexion, avec ses icônes et ses raccourcis" do
    get "/manifest.json"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/manifest+json")
    manifest = JSON.parse(response.body)
    expect(manifest).to include("short_name" => "Claudy", "display" => "standalone", "start_url" => "/?source=pwa")
    expect(manifest["icons"].map { |icon| icon["purpose"] }).to include("any", "maskable")
    expect(manifest["shortcuts"].map { |shortcut| shortcut["name"] })
      .to eq(["Nouveau séjour", "Agenda du jour", "Compter la caisse"])

    files = manifest["icons"].map { |icon| icon["src"] } + manifest["shortcuts"].flat_map { |s| s["icons"].map { |i| i["src"] } }
    files.uniq.each { |src| expect(Rails.public_path.join(src.delete_prefix("/"))).to exist }
  end

  it "met en cache des fichiers qui existent" do
    worker = Rails.public_path.join("service-worker.js").read
    offline = worker[/const OFFLINE_URL = "([^"]+)"/, 1]
    precache = worker[/const PRECACHE = \[(.*?)\]/, 1].scan(/"([^"]+)"/).flatten
    expect(offline).to eq("/hors-ligne.html")
    [offline, *precache].each { |path| expect(Rails.public_path.join(path.delete_prefix("/"))).to exist }
  end

  it "annonce le manifeste, le bandeau hors ligne et l'invitation à installer" do
    sign_in User.create!(email: "pwa@les4sources.be", password: "password123", new_interface: true)

    get today_path

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("link[rel='manifest']")["href"]).to eq("/manifest.json")
    expect(page.at_css("meta[name='viewport']")["content"]).to include("viewport-fit=cover")
    expect(page.at_css(".ui-offline[hidden][data-controller='offline-banner']")).to be_present
    expect(page.at_css(".ui-install[hidden][data-controller='pwa-install']")).to be_present
    # Pas de service worker hors production : il garderait des fichiers que
    # Vite reconstruit.
    expect(page.at_css("meta[name='claudy-service-worker']")).to be_nil
  end

  it "rend la page de connexion installable aussi" do
    get new_user_session_path

    expect(Nokogiri::HTML(response.body).at_css("link[rel='manifest']")).to be_present
  end
end
