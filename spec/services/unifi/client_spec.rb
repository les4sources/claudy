require "rails_helper"

# Epic #348, phase 10 — le client lit l'API cloud UniFi Site Manager et ne
# lui écrit jamais. Même contrat que `TranchesDeVie::Client` : sans clé, il se
# déclare non configuré ; en panne, il rend une liste vide et se dit
# indisponible, sans jamais laisser remonter d'exception jusqu'à l'UI.
RSpec.describe Unifi::Client do
  include ActiveSupport::Testing::TimeHelpers

  let(:devices_url) { "#{described_class::BASE_URL}#{described_class::DEVICES_PATH}" }
  let(:fixture) { file_fixture("unifi_devices.json").read }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  around do |example|
    key = ENV["UNIFI_API_KEY"]
    example.run
    ENV["UNIFI_API_KEY"] = key
  end

  before { allow(Rails).to receive(:cache).and_return(cache) }

  def stub_devices(body: fixture, status: 200)
    stub_request(:get, devices_url).to_return(status: status, body: body,
                                              headers: { "Content-Type" => "application/json" })
  end

  describe "sans clé d'API" do
    before { ENV.delete("UNIFI_API_KEY") }

    it "se déclare non configuré et indisponible, sans appel réseau" do
      client = described_class.new

      expect(described_class).not_to be_configured
      expect(client).not_to be_configured
      expect(client.devices).to eq([])
      expect(client.device("F4E2C6C23F13")).to be_nil
      expect(client).not_to be_available
      expect(a_request(:any, //)).not_to have_been_made
    end
  end

  describe "avec une clé d'API" do
    before { ENV["UNIFI_API_KEY"] = "cle-de-test" }

    it "porte la clé et demande du JSON" do
      stub = stub_devices.with(headers: { "X-API-KEY" => "cle-de-test", "Accept" => "application/json" })

      described_class.new.devices

      expect(stub).to have_been_made.once
    end

    it "normalise les équipements de tous les hôtes" do
      stub_devices

      client = described_class.new
      devices = client.devices

      expect(client).to be_configured
      expect(client).to be_available
      expect(devices.map(&:id)).to eq(%w[F4E2C6C23F13 E063DA0011AA D021F9A0B0C1])
      switch = devices.first
      expect(switch).to be_a(Unifi::Device)
      expect(switch.name).to eq("Switch grange")
      expect(switch.model).to eq("USW Flex Mini")
      expect(switch.mac).to eq("F4E2C6C23F13")
      expect(switch.ip).to eq("192.168.1.21")
      expect(switch.status).to eq("online")
      expect(switch.host_name).to eq("Les 4 Sources")
      expect(switch.last_seen_at).to eq(Time.zone.parse("2026-09-28T07:41:02Z"))
      expect(devices.second.status).to eq("offline")
    end

    it "donne un nom lisible à un équipement sans nom" do
      stub_devices

      gateway = described_class.new.device("D021F9A0B0C1")

      expect(gateway.name).to eq("UCG Ultra")
    end

    it "retrouve un équipement par son identifiant" do
      stub_devices

      client = described_class.new

      expect(client.device("E063DA0011AA").name).to eq("AP gîte du Grand-Duc")
      expect(client.device("inconnu")).to be_nil
      expect(client.device(nil)).to be_nil
    end

    it "sérialise un équipement pour le JSON" do
      stub_devices

      json = described_class.new.devices.first.as_json

      expect(json).to include("id" => "F4E2C6C23F13", "status" => "online", "model" => "USW Flex Mini",
                              "host_name" => "Les 4 Sources")
      expect(Time.zone.parse(json["last_seen_at"])).to eq(Time.zone.parse("2026-09-28T07:41:02Z"))
    end

    it "garde la réponse en cache 60 secondes" do
      stub = stub_devices

      described_class.new.devices
      described_class.new.devices
      expect(stub).to have_been_made.once

      travel(61.seconds) { described_class.new.devices }
      expect(stub).to have_been_made.twice
    end

    it "rend une liste vide et se dit indisponible sur un timeout" do
      stub_request(:get, devices_url).to_timeout
      allow(Rails.logger).to receive(:warn)

      client = described_class.new

      expect(client.devices).to eq([])
      expect(client).not_to be_available
      expect(Rails.logger).to have_received(:warn).with(/UniFi/)
    end

    it "rend une liste vide et se dit indisponible sur une clé refusée" do
      stub_devices(body: "", status: 401)

      client = described_class.new

      expect(client.devices).to eq([])
      expect(client).not_to be_available
    end

    it "rend une liste vide et se dit indisponible sur une réponse illisible" do
      stub_devices(body: "<html>")

      client = described_class.new

      expect(client.devices).to eq([])
      expect(client).not_to be_available
    end

    it "rend une liste vide et se dit indisponible sur un hôte injoignable" do
      stub_request(:get, devices_url).to_raise(SocketError)

      client = described_class.new

      expect(client.devices).to eq([])
      expect(client).not_to be_available
    end

    it "ne met pas une panne en cache : l'appel suivant réessaie" do
      stub_request(:get, devices_url).to_timeout.then.to_return(status: 200, body: fixture)

      expect(described_class.new.devices).to eq([])
      expect(described_class.new.devices.size).to eq(3)
    end
  end
end
