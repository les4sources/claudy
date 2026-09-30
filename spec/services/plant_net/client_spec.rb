require "rails_helper"

# « Placer une plante » : Pl@ntNet reçoit les photos d'un individu et répond
# ses espèces probables. Le client ne décide rien, il traduit.
RSpec.describe PlantNet::Client do
  let(:endpoint) { %r{\Ahttps://my-api\.plantnet\.org/v2/identify/all} }
  let(:image) { { io: StringIO.new("jpeg"), filename: "feuille.jpg", content_type: "image/jpeg" } }

  it "sans clé, se déclare non configuré et ne part pas" do
    client = described_class.new(api_key: nil)
    expect(client).not_to be_configured
    expect { client.identify([image]) }.to raise_error(described_class::NotConfigured)
    expect(a_request(:any, //)).not_to have_been_made
  end

  context "avec une clé" do
    subject(:client) { described_class.new(api_key: "cle-test") }

    it "envoie les photos en multipart et lit les candidats, du plus probable au moins probable" do
      stub = stub_request(:post, endpoint)
             .with(query: hash_including("api-key" => "cle-test", "lang" => "fr"))
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
               results: [
                 { score: 0.83,
                   species: { scientificNameWithoutAuthor: "Malus domestica", scientificNameAuthorship: "(Suckow) Borkh.",
                              genus: { scientificNameWithoutAuthor: "Malus" },
                              family: { scientificNameWithoutAuthor: "Rosaceae" },
                              commonNames: ["Pommier", "Pommier domestique"] },
                   gbif: { id: "3001509" } },
                 { score: 0.07,
                   species: { scientificNameWithoutAuthor: "Malus sylvestris", commonNames: [] } }
               ]
             }.to_json)

      candidates = client.identify([image, image.merge(filename: "fleur.jpg")])

      expect(stub).to have_been_made
      expect(a_request(:post, endpoint).with { |req| req.body.include?("feuille.jpg") && req.body.include?("fleur.jpg") && req.body.include?("auto") })
        .to have_been_made
      expect(candidates.map(&:latin_name)).to eq(["Malus domestica", "Malus sylvestris"])
      expect(candidates.first).to have_attributes(family: "Rosaceae", genus: "Malus", score: 0.83,
                                                  common_names: ["Pommier", "Pommier domestique"], gbif_id: "3001509")
    end

    it "rend une liste vide quand Pl@ntNet ne voit pas de plante (404)" do
      stub_request(:post, endpoint).to_return(status: 404, body: { message: "Species not found" }.to_json)
      expect(client.identify([image])).to eq([])
    end

    it "traduit une erreur du service en erreur typée" do
      stub_request(:post, endpoint).to_return(status: 401, body: "Invalid api key")
      expect { client.identify([image]) }.to raise_error(described_class::Error, /401/)
    end

    it "refuse plus de cinq photos sans appeler le service" do
      expect { client.identify([image] * 6) }.to raise_error(described_class::Error, /5 photos/)
      expect(a_request(:any, //)).not_to have_been_made
    end
  end
end
