require "rails_helper"

# Écrire des événements par l'API agent : reprendre l'agenda de l'ancien site,
# publier une nouvelle date d'une série, marquer une date complète — sans
# passer par le formulaire.
RSpec.describe "API v1 — événements", type: :request do
  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }
  let!(:ateliers) { EventCategory.create!(name: "Ateliers", color: "orange") }
  let!(:parties) { EventCategory.create!(name: "Parties", color: "amber") }

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def body = JSON.parse(response.body)

  def poste(attrs)
    post "/api/v1/events", params: { event: attrs }.to_json, headers: headers
  end

  def event!(attrs = {})
    starts = Time.zone.parse("2026-10-03 09:30")
    Event.create!({ name: "Atelier d’écriture", event_category: ateliers, starts_at: starts,
                    ends_at: starts + 7.hours }.merge(attrs))
  end

  let(:atelier) do
    {
      name: "Atelier d’écriture",
      category: "ateliers",
      starts_at: "2026-10-03T09:30",
      ends_at: "2026-10-03T16:30",
      summary: "Une journée pour écrire au jardin.",
      public_description: "<p>On écrit <strong>ensemble</strong>.</p>",
      price_text: "45 €",
      registration_url: "https://www.billetweb.fr/atelier-ecriture",
      location: "Les 4 Sources, Yvoir",
      slug: "weekend-cratif",
      published: true
    }
  end

  describe "authentification" do
    it "refuse une écriture sans jeton" do
      expect {
        post "/api/v1/events", params: { event: atelier }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      }.not_to change(Event, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/events" do
    it "crée et publie un événement, sous le slug demandé" do
      expect { poste(atelier) }.to change(Event, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(body["meta"]["created"]).to be(true)
      event = Event.last
      expect(event.name).to eq("Atelier d’écriture")
      expect(event.event_category).to eq(ateliers)
      expect(event.slug).to eq("weekend-cratif")
      expect(event).to be_published
      expect(event.url).to eq("https://www.billetweb.fr/atelier-ecriture")
      expect(event.starts_at).to eq(Time.zone.parse("2026-10-03 09:30"))
      expect(event.public_description.body.to_html).to include("<strong>ensemble</strong>")
      expect(body["data"]).to include("slug" => "weekend-cratif", "published" => true,
                                      "registration_url" => "https://www.billetweb.fr/atelier-ecriture",
                                      "public_url" => "https://www.les4sources.be/evenements/weekend-cratif")
    end

    it "est un upsert sur le slug : rejouer l'appel met à jour sans dupliquer" do
      poste(atelier)
      expect {
        poste(atelier.merge(name: "COMPLET ! Atelier d’écriture"))
      }.not_to change(Event, :count)

      expect(response).to have_http_status(:ok)
      expect(body["meta"]["created"]).to be(false)
      expect(Event.find_by(slug: "weekend-cratif").name).to eq("COMPLET ! Atelier d’écriture")
    end

    it "une date seule donne une journée entière" do
      poste(atelier.merge(starts_at: "2026-10-08", ends_at: "2026-10-10"))

      expect(response).to have_http_status(:created)
      expect(Event.last).to be_all_day
      expect(body["data"]["all_day"]).to be(true)
    end

    it "sans `published`, l'événement reste un brouillon" do
      poste(atelier.except(:published))

      expect(Event.last).to be_draft
      expect(body["data"]["published"]).to be(false)
    end

    it "refuse une catégorie inconnue sans rien créer" do
      expect { poste(atelier.merge(category: "inconnue")) }.not_to change(Event, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["message"]).to include("Catégorie inconnue")
    end

    it "refuse une date illisible" do
      expect { poste(atelier.merge(starts_at: "bientôt")) }.not_to change(Event, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["message"]).to include("starts_at")
    end

    it "renvoie les erreurs de validation" do
      poste(atelier.merge(name: ""))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["messages"]).not_to be_empty
    end

    describe "image_url" do
      let(:png) { File.binread(Rails.root.join("spec/fixtures/files/capture.png")) }

      before do
        allow(Resolv).to receive(:getaddresses).and_call_original
        allow(Resolv).to receive(:getaddresses).with("images.example.org").and_return(["93.184.216.34"])
        allow(Resolv).to receive(:getaddresses).with("intranet.example.org").and_return(["10.0.0.5"])
      end

      it "télécharge et attache l'image" do
        stub_request(:get, "https://images.example.org/atelier.png")
          .to_return(status: 200, body: png, headers: { "Content-Type" => "image/png" })

        poste(atelier.merge(image_url: "https://images.example.org/atelier.png"))

        expect(response).to have_http_status(:created)
        expect(Event.last.image).to be_attached
        expect(Event.last.image.filename.to_s).to eq("atelier.png")
      end

      it "refuse ce qui n'est pas une image, sans créer l'événement" do
        stub_request(:get, "https://images.example.org/page.html")
          .to_return(status: 200, body: "<html></html>", headers: { "Content-Type" => "text/html" })

        expect { poste(atelier.merge(image_url: "https://images.example.org/page.html")) }.not_to change(Event, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(body["message"]).to include("pas une image")
      end

      it "refuse le HTTP simple et les adresses privées" do
        poste(atelier.merge(image_url: "http://images.example.org/atelier.png"))
        expect(body["message"]).to include("https")

        poste(atelier.merge(image_url: "https://intranet.example.org/atelier.png"))
        expect(body["message"]).to include("privée")
        expect(Event.count).to eq(0)
      end
    end
  end

  describe "GET /api/v1/events" do
    it "liste brouillons et publiés, filtrables" do
      draft = event!
      published = event!(name: "Pizza Party", event_category: parties, slug: "pizza-party-octobre-2026",
                         published_at: Time.current, starts_at: Time.zone.parse("2026-10-09 18:30"),
                         ends_at: Time.zone.parse("2026-10-09 22:30"))

      get "/api/v1/events", headers: headers
      expect(body["data"].map { |e| e["id"] }).to eq([draft.id, published.id])

      get "/api/v1/events", params: { published: "false" }, headers: headers
      expect(body["data"].map { |e| e["id"] }).to eq([draft.id])

      get "/api/v1/events", params: { category: "parties" }, headers: headers
      expect(body["data"].map { |e| e["id"] }).to eq([published.id])

      get "/api/v1/events", params: { from: "2026-10-05" }, headers: headers
      expect(body["data"].map { |e| e["id"] }).to eq([published.id])

      get "/api/v1/events", params: { q: "écriture" }, headers: headers
      expect(body["data"].map { |e| e["id"] }).to eq([draft.id])
    end
  end

  describe "PATCH /api/v1/events/:id" do
    it "publie un brouillon existant sous un slug choisi" do
      draft = event!

      patch "/api/v1/events/#{draft.id}", params: { event: { published: true, slug: "weekend-cratif" } }.to_json,
                                          headers: headers

      expect(response).to have_http_status(:ok)
      expect(draft.reload).to be_published
      expect(draft.slug).to eq("weekend-cratif")
    end

    it "ne change pas le slug d'une fiche publiée" do
      published = event!(slug: "weekend-cratif", published_at: Time.current)

      patch "/api/v1/events/#{published.id}", params: { event: { slug: "autre-chose" } }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(published.reload.slug).to eq("weekend-cratif")
    end

    it "dépublie" do
      published = event!(slug: "weekend-cratif", published_at: Time.current)

      patch "/api/v1/events/#{published.id}", params: { event: { published: false } }.to_json, headers: headers

      expect(published.reload).to be_draft
      expect(published.slug).to eq("weekend-cratif")
    end
  end

  describe "DELETE /api/v1/events/:id" do
    it "met l'événement à la corbeille" do
      event = event!

      delete "/api/v1/events/#{event.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(Event.find_by(id: event.id)).to be_nil
      expect(Event.unscoped.find(event.id).deleted_at).to be_present
    end
  end

  describe "catégories" do
    it "se listent avec leur pôle et reçoivent un pôle" do
      get "/api/v1/event_categories", headers: headers
      expect(body["data"].map { |c| c["slug"] }).to eq(%w[ateliers parties])

      patch "/api/v1/event_categories/#{parties.id}", params: { event_category: { pole: "convivialite" } }.to_json,
                                                       headers: headers

      expect(response).to have_http_status(:ok)
      expect(parties.reload.pole).to eq("convivialite")
      expect(body["data"]).to include("pole" => "convivialite", "pole_label" => "Convivialité")
    end

    it "se créent, et POST est un upsert sur le slug dérivé du nom" do
      expect {
        post "/api/v1/event_categories", params: { event_category: { name: "Projections", pole: "convivialite" } }.to_json,
                                         headers: headers
      }.to change(EventCategory, :count).by(1)
    
      expect(response).to have_http_status(:created)
      expect(body["meta"]["created"]).to be(true)
      expect(body["data"]).to include("slug" => "projections", "pole" => "convivialite", "color" => "#224246")
    
      expect {
        post "/api/v1/event_categories", params: { event_category: { name: "Projections", color: "#0891b2" } }.to_json,
                                         headers: headers
      }.not_to change(EventCategory, :count)
      expect(response).to have_http_status(:ok)
      expect(body["meta"]["created"]).to be(false)
      expect(EventCategory.find_by(slug: "projections")).to have_attributes(color: "#0891b2", pole: "convivialite")
    end
    
    it "gardent leur slug quand on les renomme" do
      patch "/api/v1/event_categories/#{parties.id}", params: { event_category: { name: "Soirées", slug: "soirees" } }.to_json,
                                                       headers: headers
    
      expect(parties.reload).to have_attributes(name: "Soirées", slug: "parties")
    end
    
    it "refusent un pôle hors charte" do
      patch "/api/v1/event_categories/#{parties.id}", params: { event_category: { pole: "fête" } }.to_json,
                                                       headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
