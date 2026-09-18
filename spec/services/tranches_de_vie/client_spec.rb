require "rails_helper"

# Issue #339 — le client lit l'API de Tranches de Vie et ne lui écrit jamais.
RSpec.describe TranchesDeVie::Client do
  around do |example|
    url, key = ENV["TRANCHESDEVIE_API_URL"], ENV["TRANCHESDEVIE_API_KEY"]
    example.run
    ENV["TRANCHESDEVIE_API_URL"] = url
    ENV["TRANCHESDEVIE_API_KEY"] = key
  end

  describe "sans clé d'API" do
    before { tdv_env_off! }

    it "se déclare non configuré" do
      expect(described_class).not_to be_configured
      expect(described_class.new).not_to be_configured
    end

    it "refuse de partir plutôt que d'échouer en vol" do
      expect { described_class.new.order(1) }.to raise_error(described_class::NotConfigured)
      expect(a_request(:any, //)).not_to have_been_made
    end
  end

  describe "avec une clé d'API" do
    before { tdv_env! }

    it "porte le jeton et les filtres du contrat" do
      stub = stub_tdv_index([tdv_order])

      described_class.new.private_parties(held_on_from: Date.new(2026, 10, 8), held_on_to: Date.new(2026, 10, 12))

      expect(stub).to have_been_made
      expect(
        a_request(:get, "#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders")
          .with(headers: { "Authorization" => "Bearer #{TranchesDeVieHelpers::API_KEY}" },
                query: hash_including({ "kind" => "private_party", "paid" => "true",
                                        "held_on_from" => "2026-10-08", "held_on_to" => "2026-10-12" }))
      ).to have_been_made
    end

    it "suit la pagination tant qu'une page suivante est annoncée" do
      stub_request(:get, "#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders")
        .with(query: hash_including({ "page" => "1" }))
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { data: [tdv_order(id: 1)], _links: { next: "/api/v1/orders?page=2" } }.to_json)
      stub_request(:get, "#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders")
        .with(query: hash_including({ "page" => "2" }))
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { data: [tdv_order(id: 2)], _links: { next: nil } }.to_json)

      orders = described_class.new.private_parties(held_on_from: Date.current, held_on_to: Date.current)
      expect(orders.map { |o| o["id"] }).to eq([1, 2])
    end

    it "renvoie une commande par son identifiant" do
      stub_tdv_order(tdv_order(id: 77))
      expect(described_class.new.order(77)["order_number"]).to eq("TV-20261009-0077")
    end

    it "traduit un 404 en erreur typée" do
      stub_tdv_order_missing(404_404)
      expect { described_class.new.order(404_404) }.to raise_error(described_class::NotFound)
    end

    it "traduit un timeout en erreur typée avec un message lisible" do
      stub_request(:get, %r{#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders}).to_timeout

      expect { described_class.new.order(1) }
        .to raise_error(described_class::Error, /n'a pas répondu à temps/)
    end

    it "traduit une clé refusée en erreur typée" do
      stub_request(:get, %r{#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders}).to_return(status: 401, body: "")
      expect { described_class.new.order(1) }.to raise_error(described_class::Error, /refusé la clé/)
    end

    it "traduit une réponse illisible en erreur typée" do
      stub_request(:get, %r{#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders}).to_return(status: 200, body: "<html>")
      expect { described_class.new.order(1) }.to raise_error(described_class::Error, /illisible/)
    end
  end
end
