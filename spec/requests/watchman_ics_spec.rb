require "rails_helper"

# issue #142 — le flux iCal des gardes doit être récupérable par Google Agenda :
# anonymement (aucun cookie, aucune session Devise) et scellé par un seul jeton.
RSpec.describe "GET /watchman.ics", type: :request do
  let(:token) { "jeton-de-test-tres-long-et-aleatoire" }
  let!(:role) do
    Role.find_or_create_by!(id: Watchmen::IcalFeed::WATCHMAN_ROLE_ID) { |r| r.name = "Veilleur·euse" }
  end

  def with_token(value)
    original = ENV["WATCHMAN_ICS_TOKEN"]
    ENV["WATCHMAN_ICS_TOKEN"] = value
    yield
  ensure
    ENV["WATCHMAN_ICS_TOKEN"] = original
  end

  describe "protection par jeton" do
    it "renvoie 404 sans jeton" do
      with_token(token) { get "/watchman.ics" }

      expect(response).to have_http_status(:not_found)
    end

    it "renvoie 404 avec un jeton faux" do
      with_token(token) { get "/watchman.ics", params: { token: "pas-le-bon" } }

      expect(response).to have_http_status(:not_found)
    end

    it "renvoie 404 avec un jeton de la bonne longueur mais faux" do
      with_token(token) { get "/watchman.ics", params: { token: token.sub(/.\z/, "X") } }

      expect(response).to have_http_status(:not_found)
    end

    it "renvoie 404 quand ENV[\"WATCHMAN_ICS_TOKEN\"] est vide — jamais de flux ouvert par défaut" do
      with_token("") { get "/watchman.ics", params: { token: "" } }

      expect(response).to have_http_status(:not_found)
    end

    it "renvoie 404 quand ENV[\"WATCHMAN_ICS_TOKEN\"] est absent" do
      with_token(nil) { get "/watchman.ics", params: { token: token } }

      expect(response).to have_http_status(:not_found)
    end

    it "ne renvoie ni 401 ni 403 : on ne confirme pas l'existence du flux" do
      with_token(token) { get "/watchman.ics", params: { token: "pas-le-bon" } }

      expect(response).not_to have_http_status(:unauthorized)
      expect(response).not_to have_http_status(:forbidden)
      expect(response.body).to be_blank
    end
  end

  describe "avec le bon jeton" do
    let!(:garde) do
      HumanRole.create!(human: Human.create!(name: "Ana"), role: role,
                        date: Date.new(2026, 8, 12), status: :selected)
    end

    it "renvoie 200 et un Content-Type text/calendar en UTF-8" do
      with_token(token) { get "/watchman.ics", params: { token: token } }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to eq("text/calendar; charset=utf-8")
    end

    it "est accessible SANS être connecté — aucune redirection vers Devise" do
      # Aucun `sign_in` ici : c'est exactement le besoin (Google Agenda est anonyme).
      with_token(token) { get "/watchman.ics", params: { token: token } }

      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
      expect(response.body).to include("BEGIN:VCALENDAR")
    end

    it "sert le flux des gardes" do
      with_token(token) { get "/watchman.ics", params: { token: token } }

      body = response.body.gsub("\r\n ", "")

      expect(body).to include("SUMMARY:Garde : Ana")
      expect(body).to include("UID:garde-20260812@claudy.les4sources.be")
      expect(body).to include("DTSTART;VALUE=DATE:20260812")
      expect(body).to include("DTEND;VALUE=DATE:20260813")
      expect(body).to end_with("END:VCALENDAR\r\n")
    end

    it "ne modifie aucune donnée — le flux est strictement en lecture" do
      empreinte = -> { [HumanRole.count, Human.unscoped.count, HumanRole.pluck(:updated_at)] }
      avant = empreinte.call

      with_token(token) { get "/watchman.ics", params: { token: token } }

      expect(empreinte.call).to eq(avant)
    end
  end
end
