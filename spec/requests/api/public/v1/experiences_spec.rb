require "rails_helper"

RSpec.describe "Api::Public::V1::Experiences", type: :request do
  def json
    JSON.parse(response.body)
  end

  let!(:carrier) { Human.create!(name: "Romain Gauthier", email: "romain@example.com") }
  let!(:published) do
    Experience.create!(
      name: "Grimpe encadrée dans les arbres",
      summary: "Une initiation à la grimpe d'arbre, encadrée, dès 8 ans.",
      description: "<div>Casque et baudrier <em>fournis</em>.</div>",
      duration: "2 h",
      duration_hours: 2,
      price_cents: 2_500,
      fixed_price_cents: 0,
      min_participants: 4,
      max_participants: 12,
      human: carrier,
      published_at: 1.week.ago
    )
  end
  let!(:draft) { Experience.create!(name: "Activité en préparation", price_cents: 1_000) }
  let!(:deleted) do
    Experience.create!(name: "Activité retirée", published_at: 1.week.ago).tap { |experience| experience.soft_delete!(validate: false) }
  end
  let!(:soon) do
    ExperienceAvailability.create!(experience: published, available_on: 10.days.from_now.to_date,
                                   starts_at: "14:00", duration_minutes: 120, max_participants: 5)
  end
  let!(:far) do
    ExperienceAvailability.create!(experience: published, available_on: 8.months.from_now.to_date,
                                   starts_at: "14:00", duration_minutes: 120)
  end
  let!(:past) do
    ExperienceAvailability.create!(experience: published, available_on: 10.days.ago.to_date,
                                   starts_at: "14:00", duration_minutes: 120)
  end

  describe "GET /api/public/v1/experiences" do
    it "ne renvoie que les activités publiées et vivantes, dans la forme du contrat" do
      get "/api/public/v1/experiences"

      expect(response).to have_http_status(:ok)
      names = json["experiences"].map { |experience| experience["name"] }
      expect(names).to eq(["Grimpe encadrée dans les arbres"])

      experience = json["experiences"].first
      expect(experience.keys).to contain_exactly(
        "id", "slug", "name", "summary", "description_html", "duration_text", "duration_minutes",
        "price", "fixed_price", "min_participants", "max_participants", "carrier",
        "availabilities", "booking_url", "published_at", "updated_at", "path"
      )
      expect(experience["slug"]).to eq("grimpe-encadree-dans-les-arbres")
      expect(experience["path"]).to eq("/catalogue/grimpe-encadree-dans-les-arbres")
      expect(experience["duration_text"]).to eq("2 h")
      expect(experience["duration_minutes"]).to eq(120)
      expect(experience["price"]).to eq("amount_cents" => 2_500, "currency" => "EUR", "per" => "participant")
      expect(experience["fixed_price"]).to eq("amount_cents" => 0, "currency" => "EUR")
      expect(experience["min_participants"]).to eq(4)
      expect(experience["max_participants"]).to eq(12)
      expect(experience["booking_url"]).to eq("http://www.example.com/reservation")
      expect(experience["description_html"]).to include("<em>fournis</em>")
      expect(experience).not_to have_key("image")
    end

    it "ne désigne le porteur que par son prénom, sans e-mail" do
      get "/api/public/v1/experiences"

      expect(json["experiences"].first["carrier"]).to eq("name" => "Romain")
      expect(response.body).not_to include("Gauthier")
      expect(response.body).not_to include("romain@example.com")
    end

    it "liste les créneaux à venir sur six mois avec les places restantes" do
      get "/api/public/v1/experiences"

      availabilities = json["experiences"].first["availabilities"]
      expect(availabilities).to eq([
        { "date" => soon.available_on.iso8601, "starts_at" => "14:00", "ends_at" => "16:00", "spots_left" => 5 }
      ])
    end

    it "est cacheable cinq minutes et revalidable par ETag" do
      get "/api/public/v1/experiences"

      expect(response.headers["Cache-Control"]).to include("public", "max-age=300")
      etag = response.headers["ETag"]
      expect(etag).to be_present

      get "/api/public/v1/experiences", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
    end
  end
end
