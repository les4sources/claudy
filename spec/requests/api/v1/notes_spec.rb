require "rails_helper"

# Issue #217 — poser un post-it sur le calendrier depuis l'extérieur.
# Une pizza party réservée sur la boulangerie n'atterrissait que dans une boîte
# mail interne : l'équipe apprenait par hasard qu'un groupe de dix-huit
# personnes arrivait vendredi soir.
RSpec.describe "API v1 — notes du calendrier", type: :request do
  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def body = JSON.parse(response.body)

  def poste(attrs)
    post "/api/v1/notes", params: { note: attrs }.to_json, headers: headers
  end

  def note!(attrs = {})
    Note.create!({ body: "Grand ménage", date: Date.new(2026, 9, 11), color: "yellow" }.merge(attrs))
  end

  describe "authentification" do
    it "refuse une lecture sans header" do
      get "/api/v1/notes"

      expect(response).to have_http_status(:unauthorized)
      expect(body["error"]).to eq("unauthorized")
    end

    it "refuse une lecture avec un jeton invalide" do
      get "/api/v1/notes", headers: { "Authorization" => "Bearer nope" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuse une écriture sans header" do
      expect {
        post "/api/v1/notes", params: { note: { body: "Coucou", date: "2026-09-11" } }.to_json,
                              headers: { "CONTENT_TYPE" => "application/json" }
      }.not_to change(Note, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuse une écriture avec un jeton invalide" do
      post "/api/v1/notes", params: { note: { body: "Coucou", date: "2026-09-11" } }.to_json,
                            headers: headers.merge("Authorization" => "Bearer nope")

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/notes" do
    it "rend l'enveloppe data + meta et le type de la note" do
      note!(color: "orange", body: "Pizza Party privée", external_ref: "tranchesdevie-order-1234")

      get "/api/v1/notes", headers: headers

      expect(response).to have_http_status(:ok)
      expect(body["data"].size).to eq(1)
      expect(body["data"].first).to include(
        "type" => "note",
        "body" => "Pizza Party privée",
        "date" => "2026-09-11",
        "color" => "orange",
        "type_label" => "Pizza party",
        "external_ref" => "tranchesdevie-order-1234"
      )
      expect(body["meta"]).to include("page" => 1, "total" => 1)
    end

    it "exclut les notes supprimées en douceur" do
      note!(body: "Retirée").soft_delete!(validate: false)
      note!(body: "Toujours là")

      get "/api/v1/notes", headers: headers

      expect(body["data"].map { |n| n["body"] }).to eq(["Toujours là"])
    end

    it "trie de la note la plus récente à la plus ancienne" do
      note!(body: "Avant", date: Date.new(2026, 9, 1))
      note!(body: "Après", date: Date.new(2026, 9, 20))

      get "/api/v1/notes", headers: headers

      expect(body["data"].map { |n| n["body"] }).to eq(["Après", "Avant"])
    end

    it "borne sur from et to, inclusivement" do
      note!(body: "Veille", date: Date.new(2026, 9, 9))
      note!(body: "Pile", date: Date.new(2026, 9, 10))
      note!(body: "Lendemain", date: Date.new(2026, 9, 13))

      get "/api/v1/notes", params: { from: "2026-09-10", to: "2026-09-12" }, headers: headers

      expect(body["data"].map { |n| n["body"] }).to eq(["Pile"])
    end

    it "filtre par type de note" do
      note!(body: "Ménage", color: "yellow")
      note!(body: "Pizza", color: "orange")

      get "/api/v1/notes", params: { color: "orange" }, headers: headers

      expect(body["data"].map { |n| n["body"] }).to eq(["Pizza"])
    end

    it "filtre par référence externe" do
      note!(body: "Pizza", external_ref: "tranchesdevie-order-1234")
      note!(body: "Autre chose")

      get "/api/v1/notes", params: { external_ref: "tranchesdevie-order-1234" }, headers: headers

      expect(body["data"].map { |n| n["body"] }).to eq(["Pizza"])
    end

    it "cherche dans le corps, sans tenir compte de la casse" do
      note!(body: "Pizza Party privée")
      note!(body: "Tonte du verger")

      get "/api/v1/notes", params: { q: "pizza" }, headers: headers

      expect(body["data"].map { |n| n["body"] }).to eq(["Pizza Party privée"])
    end

    it "refuse une borne de date illisible au lieu de l'ignorer" do
      get "/api/v1/notes", params: { from: "vendredi prochain" }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/notes/:id" do
    it "rend la note" do
      note = note!(color: "orange")

      get "/api/v1/notes/#{note.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(body.dig("data", "id")).to eq(note.id)
      expect(body.dig("data", "type_label")).to eq("Pizza party")
    end

    it "rend 404 sur une note inconnue" do
      get "/api/v1/notes/0", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/notes" do
    let(:pizza_party) do
      { body: "Pizza Party privée\nSoirée : Michael Hulet - 18 personnes",
        date: "2026-09-11", color: "orange", external_ref: "tranchesdevie-order-1234" }
    end

    it "crée la note et annonce la création" do
      expect { poste(pizza_party) }.to change(Note, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "color")).to eq("orange")
      expect(body.dig("data", "type_label")).to eq("Pizza party")
      expect(body.dig("meta", "created")).to be(true)
    end

    # Le point de toute l'affaire : l'appelant rejoue son POST tant qu'il n'a
    # pas eu de réponse, et deux post-it identiques seraient pires que rien.
    it "met à jour au lieu de dupliquer quand la référence revient" do
      poste(pizza_party)

      expect { poste(pizza_party.merge(body: "Pizza Party privée\nSoirée : Michael Hulet - 22 personnes")) }
        .not_to change(Note, :count)

      expect(response).to have_http_status(:ok)
      expect(body.dig("meta", "created")).to be(false)
      expect(Note.sole.body).to eq("Pizza Party privée\nSoirée : Michael Hulet - 22 personnes")
    end

    # Sans référence, rien ne rattache le second appel au premier : on crée.
    it "crée deux notes quand aucune référence n'est fournie" do
      attrs = { body: "Tonte du verger", date: "2026-09-11", color: "pink" }

      expect { 2.times { poste(attrs) } }.to change(Note, :count).by(2)
    end

    it "repose une note dont la référence avait été supprimée en douceur" do
      poste(pizza_party)
      Note.sole.soft_delete!(validate: false)

      expect { poste(pizza_party) }.not_to raise_error

      expect(response).to have_http_status(:created)
      expect(body.dig("meta", "created")).to be(true)
      expect(Note.count).to eq(1)
      expect(Note.unscoped.count).to eq(2)
    end

    it "refuse une couleur hors des types connus" do
      expect { poste(pizza_party.merge(color: "chartreuse")) }.not_to change(Note, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["messages"].join).to match(/couleur|color/i)
    end

    it "refuse un corps vide" do
      poste(pizza_party.merge(body: ""))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuse une note sans date" do
      poste(pizza_party.except(:date))

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/notes/:id" do
    it "met à jour le corps, la date et le type" do
      note = note!

      patch "/api/v1/notes/#{note.id}",
            params: { note: { body: "Pizza Party privée", date: "2026-09-12", color: "orange" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(note.reload).to have_attributes(body: "Pizza Party privée", date: Date.new(2026, 9, 12), color: "orange")
    end

    it "refuse une couleur invalide" do
      note = note!

      patch "/api/v1/notes/#{note.id}", params: { note: { color: "chartreuse" } }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(note.reload.color).to eq("yellow")
    end

    it "refuse un corps vidé" do
      note = note!

      patch "/api/v1/notes/#{note.id}", params: { note: { body: "" } }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/notes/:id" do
    it "retire la note du calendrier sans effacer la ligne" do
      note = note!

      delete "/api/v1/notes/#{note.id}", headers: headers

      expect(response).to have_http_status(:no_content)

      get "/api/v1/notes", headers: headers
      expect(body["data"]).to be_empty
      expect(Note.unscoped.find(note.id).deleted_at).to be_present
    end
  end

  describe "découvrabilité" do
    it "annonce les notes dans l'index de l'API" do
      get "/api/v1", headers: headers

      expect(json_resources = body["resources"].map { |r| r["name"] }).to include("notes")
      expect(json_resources).to include("bookings") # l'index n'a pas perdu le reste au passage
    end

    it "décrit la ressource dans le spec OpenAPI" do
      get "/api/v1/openapi", headers: headers

      expect(body.dig("paths", "/notes")).to be_present
      expect(body.dig("paths", "/notes").keys).to contain_exactly("get", "post")
      expect(body.dig("paths", "/notes/{id}").keys).to contain_exactly("get", "patch", "delete")
      expect(body.dig("components", "schemas", "Note", "properties").keys)
        .to include("body", "date", "color", "type_label", "external_ref")
    end
  end
end
