require "rails_helper"

RSpec.describe "Api::Public::V1::EventCategories", type: :request do
  def json
    JSON.parse(response.body)
  end

  let!(:convivialite) { EventCategory.create!(name: "Convivialité", color: "#c97b3d", pole: "convivialite") }
  let!(:ateliers) { EventCategory.create!(name: "Ateliers", color: "orange") }
  let!(:deleted) { EventCategory.create!(name: "Ancienne", color: "#000000").tap { |category| category.soft_delete!(validate: false) } }

  describe "GET /api/public/v1/event_categories" do
    it "liste les catégories vivantes avec slug, nom, couleur hex et pôle" do
      get "/api/public/v1/event_categories"

      expect(response).to have_http_status(:ok)
      expect(json["categories"]).to eq([
        { "slug" => "ateliers", "name" => "Ateliers", "color" => "#ea580c" },
        { "slug" => "convivialite", "name" => "Convivialité", "color" => "#c97b3d", "pole" => "convivialite" }
      ])
    end

    it "est cacheable cinq minutes avec un ETag" do
      get "/api/public/v1/event_categories"

      expect(response.headers["Cache-Control"]).to include("public", "max-age=300")
      expect(response.headers["ETag"]).to be_present
    end
  end
end
