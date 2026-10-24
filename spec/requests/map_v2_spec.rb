require "rails_helper"

# Nouvelle interface (Michael 2026-10-24) : « Carte du domaine » montre la
# carte Terranova du lieu en plein écran ; l'ancienne interface garde la carte
# interne.
RSpec.describe "Carte du domaine en nouvelle interface", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "carte-v2@les4sources.be", password: "password123", new_interface: true) }

  before { sign_in user }

  it "intègre la carte Terranova, avec un lien pour l'ouvrir à part" do
    get "/map"

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("iframe.ui-tn-frame")["src"]).to start_with("https://terranova.semisto.org/p/les-4-sources")
    expect(doc.at_css("a.ui-tn-open")["target"]).to eq("_blank")
    expect(doc.at_css("body")["class"]).to include("ui-v2-map")
  end

  it "garde la carte interne pour l'ancienne interface" do
    user.update!(new_interface: false)

    get "/map"

    expect(response.body).not_to include("ui-tn-frame")
  end
end
