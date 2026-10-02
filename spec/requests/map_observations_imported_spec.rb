require "rails_helper"

# Un relevé importé d'observations.be : sa fiche dit d'où il vient, qui l'a
# observé, et renvoie à la fiche d'origine.
RSpec.describe "Carte du domaine — relevé importé d'observations.be", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-obs@les4sources.be", password: "password123") }
  let(:layer) { MapLayer.for_kind(:biodiversity) }
  let!(:record) do
    layer.map_features.create!(
      feature_kind: "observation", geometry: { "type" => "Point", "coordinates" => [4.90769, 50.341339] },
      properties: { "realm" => "fungi", "species_common" => "Lépiote élevée", "species_latin" => "Macrolepiota procera",
                    "observed_on" => "2023-09-30", "count" => 12, "source" => "observations.be", "source_id" => "289302713",
                    "source_url" => "https://observations.be/observation/289302713/", "observer_name" => "François Hela",
                    "photos_count" => 5 }
    )
  end

  before { sign_in user }

  it "montre la source, l'observateur externe et le lien vers la fiche d'origine" do
    get map_feature_path(record)

    page = Nokogiri::HTML(response.body)
    source = page.at_css("[data-observation-source]")
    expect(source.text).to include("Importé d'observations.be", "François Hela", "5 photos")
    link = source.at_css("a")
    expect(link["href"]).to eq("https://observations.be/observation/289302713/")
    expect(link["target"]).to eq("_blank")
    expect(page.at_css("[data-observation-external-observer]").text).to eq("François Hela")
    expect(page.at_css("select[name='observation[observer_id]']")).to be_nil
    expect(page.css("input[name='observation[realm]']").map { |input| input["value"] }).to include("fungi")
  end

  it "refuse un lien de source qui n'est pas une adresse web" do
    record.properties = record.properties.merge("source_url" => "javascript:alert(1)")

    expect(record).not_to be_valid
    expect(record.errors.full_messages.join).to include("adresse web")
  end
end
