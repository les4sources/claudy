require "rails_helper"

RSpec.describe WebsiteRebuildJob, queue_adapter: :test do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  around do |example|
    previous = ENV.slice("WEBSITE_REBUILD_WEBHOOK_URL", "WEBSITE_REBUILD_ALLOW_NON_PRODUCTION", "WEBSITE_REBUILD_WEBHOOK_TOKEN")
    ENV.delete("WEBSITE_REBUILD_WEBHOOK_URL")
    ENV.delete("WEBSITE_REBUILD_ALLOW_NON_PRODUCTION")
    ENV.delete("WEBSITE_REBUILD_WEBHOOK_TOKEN")
    example.run
  ensure
    %w[WEBSITE_REBUILD_WEBHOOK_URL WEBSITE_REBUILD_ALLOW_NON_PRODUCTION WEBSITE_REBUILD_WEBHOOK_TOKEN].each do |key|
      previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key)
    end
  end

  describe ".request!" do
    it "regroupe : plusieurs demandes dans la fenêtre n'enfilent qu'un seul job, différé de deux minutes" do
      expect(described_class.request!).to be(true)
      expect(described_class.request!).to be(false)
      expect(described_class.request!).to be(false)

      expect(described_class).to have_been_enqueued.once
    end

    it "réarme après l'exécution du job" do
      described_class.request!
      described_class.new.perform
      expect(described_class.request!).to be(true)
    end

    it "ne diffère pas sous l'adaptateur inline (il ne sait pas) : exécute tout de suite sans planter" do
      previous = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :inline
      expect(described_class).not_to receive(:post)
      expect { described_class.request! }.not_to raise_error
    ensure
      ActiveJob::Base.queue_adapter = previous
    end
  end

  describe "#perform" do
    it "ne fait rien sans URL de webhook" do
      expect(described_class).not_to receive(:post)
      expect(described_class.new.perform).to eq(:skipped)
    end

    it "n'appelle jamais le webhook hors production sans autorisation explicite" do
      ENV["WEBSITE_REBUILD_WEBHOOK_URL"] = "https://deploy.example.org/hook"
      expect(described_class).not_to receive(:post)
      expect(described_class.new.perform).to eq(:skipped)
    end

    it "appelle le webhook une fois autorisé et libère le verrou" do
      ENV["WEBSITE_REBUILD_WEBHOOK_URL"] = "https://deploy.example.org/hook"
      ENV["WEBSITE_REBUILD_ALLOW_NON_PRODUCTION"] = "1"
      cache.write(described_class::LOCK_KEY, 1)
      response = instance_double(Net::HTTPOK, code: "200")
      expect(described_class).to receive(:post).with("https://deploy.example.org/hook").and_return(response)

      expect(described_class.new.perform).to eq("200")
      expect(cache.read(described_class::LOCK_KEY)).to be_nil
    end
  end
end
