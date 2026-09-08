require "rails_helper"

# API publique lue par le site les4sources.be au build — contrat
# `docs/CLAUDY.md` du repo du site. Sans authentification, lecture seule,
# aucune donnée personnelle.
RSpec.describe "Api::Public::V1::Events", type: :request do
  def json
    JSON.parse(response.body)
  end

  # PNG 1×1 pour les tests d'image (dimensions connues : 1 × 1).
  PNG_1X1 = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  )

  let!(:category) { EventCategory.create!(name: "Convivialité", color: "#c97b3d", pole: "convivialite") }
  let(:next_week) { 7.days.from_now.change(hour: 18, min: 30) }

  let!(:published) do
    Event.create!(
      name: "Pizza party de septembre",
      event_category: category,
      starts_at: next_week,
      ends_at: next_week + 3.hours + 30.minutes,
      summary: "Le four à bois est chaud, amenez vos ami·es.",
      location: "Les 4 Sources, Yvoir",
      price_text: "Pizzas à prix libre",
      url: "https://example.org/inscription",
      attendees: 42,
      sales_amount_cents: 12_345,
      notes: "<div>Note interne : appeler le fournisseur</div>",
      public_description: "<div>Amenez vos <strong>ami·es</strong>.<script>alert(1)</script><img src=\"/rails/active_storage/blobs/x.jpg\"></div>",
      published_at: 3.days.ago
    )
  end
  let!(:draft) do
    Event.create!(name: "Brouillon secret", event_category: category, starts_at: next_week, ends_at: next_week + 1.hour)
  end
  let!(:ancient) do
    Event.create!(name: "Vieil événement", event_category: category,
                  starts_at: 2.years.ago, ends_at: 2.years.ago + 2.hours, published_at: 2.years.ago)
  end
  let!(:deleted) do
    Event.create!(name: "Événement supprimé", event_category: category,
                  starts_at: next_week, ends_at: next_week + 1.hour, published_at: 1.day.ago)
         .tap { |event| event.soft_delete!(validate: false) }
  end

  describe "GET /api/public/v1/events" do
    it "ne renvoie que les événements publiés, vivants et de moins d'un an, dans la forme du contrat" do
      get "/api/public/v1/events"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(json).to include("generated_at", "events")

      titles = json["events"].map { |event| event["title"] }
      expect(titles).to eq(["Pizza party de septembre"])

      event = json["events"].first
      expect(event.keys).to contain_exactly(
        "id", "slug", "title", "summary", "description_html", "starts_at", "ends_at", "all_day",
        "category", "location", "price_text", "registration_url", "published_at", "updated_at", "path"
      )
      expect(event["id"]).to eq(published.id)
      expect(event["slug"]).to eq(published.slug)
      expect(event["path"]).to eq("/evenements/#{published.slug}")
      expect(event["all_day"]).to be(false)
      expect(event["starts_at"]).to eq(published.starts_at.iso8601)
      expect(event["ends_at"]).to eq(published.ends_at.iso8601)
      expect(event["summary"]).to eq("Le four à bois est chaud, amenez vos ami·es.")
      expect(event["location"]).to eq("Les 4 Sources, Yvoir")
      expect(event["price_text"]).to eq("Pizzas à prix libre")
      expect(event["registration_url"]).to eq("https://example.org/inscription")
      expect(event["published_at"]).to eq(published.published_at.iso8601)
      expect(event["category"]).to eq(
        "slug" => "convivialite", "name" => "Convivialité", "color" => "#c97b3d", "pole" => "convivialite"
      )
    end

    it "rend la description publique assainie, sans script, avec des URLs absolues — jamais les notes internes" do
      get "/api/public/v1/events"

      html = json["events"].first["description_html"]
      expect(html).to include("<strong>ami·es</strong>")
      expect(html).not_to include("<script")
      expect(html).to include(%(src="http://www.example.com/rails/active_storage/blobs/x.jpg"))
      expect(response.body).not_to include("appeler le fournisseur")
    end

    it "n'expose aucune donnée interne ni personnelle" do
      get "/api/public/v1/events"

      expect(response.body).not_to match(/attendees|sales_amount|notes|email|phone|deleted_at/)
    end

    it "omet l'image quand il n'y en a pas et la décrit en URL absolue quand elle existe" do
      get "/api/public/v1/events"
      expect(json["events"].first).not_to have_key("image")

      published.image.attach(io: StringIO.new(PNG_1X1), filename: "affiche.png", content_type: "image/png")
      get "/api/public/v1/events"

      image = json["events"].first["image"]
      expect(image["url"]).to start_with("http://www.example.com/rails/active_storage/")
      expect(image["alt"]).to eq("Pizza party de septembre")
    end

    it "filtre sur from / to" do
      get "/api/public/v1/events", params: { from: 3.years.ago.to_date.iso8601 }
      expect(json["events"].map { |event| event["title"] }).to contain_exactly("Pizza party de septembre", "Vieil événement")

      get "/api/public/v1/events", params: { from: 3.years.ago.to_date.iso8601, to: 1.year.ago.to_date.iso8601 }
      expect(json["events"].map { |event| event["title"] }).to eq(["Vieil événement"])

      get "/api/public/v1/events", params: { from: "n'importe quoi" }
      expect(response).to have_http_status(:ok)
      expect(json["events"].map { |event| event["title"] }).to eq(["Pizza party de septembre"])
    end

    it "est cacheable cinq minutes et revalidable par ETag" do
      get "/api/public/v1/events"

      expect(response.headers["Cache-Control"]).to include("public")
      expect(response.headers["Cache-Control"]).to include("max-age=300")
      etag = response.headers["ETag"]
      expect(etag).to be_present

      get "/api/public/v1/events", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)

      published.update!(summary: "Nouveau résumé")
      get "/api/public/v1/events", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)
    end

    it "ne demande aucune authentification et refuse toute écriture" do
      get "/api/public/v1/events"
      expect(response).to have_http_status(:ok)

      expect { post "/api/public/v1/events", params: { event: { name: "Intrus" } } }
        .to raise_error(ActionController::RoutingError)
      expect { patch "/api/public/v1/events/#{published.id}", params: { event: { name: "Intrus" } } }
        .to raise_error(ActionController::RoutingError)
      expect { delete "/api/public/v1/events/#{published.id}" }
        .to raise_error(ActionController::RoutingError)
    end
  end
end
