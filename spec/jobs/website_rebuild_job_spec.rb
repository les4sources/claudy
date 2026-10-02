require "rails_helper"

# Le site les4sources.be se reconstruit quand une fiche publiée change.
#
# Panne d'origine (2026-09-29) : le regroupement tenait dans un verrou du cache
# FICHIER, dont `unless_exist` ignore l'expiration. Un seul job perdu (le
# processus redémarre pendant les deux minutes d'attente) laissait le verrou en
# place pour toujours : plus aucune publication ne reconstruisait le site.
RSpec.describe WebsiteRebuildJob, queue_adapter: :test do
  include ActiveSupport::Testing::TimeHelpers

  # Le processus redémarre : le job différé disparaît de la file en mémoire.
  def lose_enqueued_jobs! = ActiveJob::Base.queue_adapter.enqueued_jobs.clear

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

  def enable_webhook!
    ENV["WEBSITE_REBUILD_WEBHOOK_URL"] = "https://deploy.example.org/hook"
    ENV["WEBSITE_REBUILD_ALLOW_NON_PRODUCTION"] = "1"
  end

  def response(code = "200") = instance_double(Net::HTTPResponse, code: code)

  describe ".request!" do
    it "regroupe : plusieurs demandes dans la fenêtre n'ouvrent qu'une demande et n'enfilent qu'un job, différé" do
      expect(described_class.request!).to be(true)
      expect(described_class.request!).to be(false)
      expect(described_class.request!).to be(false)

      expect(described_class).to have_been_enqueued.once
      expect(WebsiteRebuild.count).to eq(1)
      expect(WebsiteRebuild.last).to have_attributes(status: "pending", requests_count: 3, trigger: "publication")
    end

    it "réarme après l'exécution du job" do
      enable_webhook!
      allow(described_class).to receive(:post).and_return(response)

      described_class.request!
      described_class.new.perform

      expect(described_class.request!).to be(true)
      expect(WebsiteRebuild.pluck(:status)).to contain_exactly("sent", "pending")
    end

    it "relance une demande dont le job a été perdu (redémarrage pendant la fenêtre)" do
      travel_to(Time.zone.parse("2026-09-29 14:02")) { described_class.request! }
      lose_enqueued_jobs!

      travel_to(Time.zone.parse("2026-09-29 16:00")) do
        expect(described_class.request!).to be(true)
      end
      expect(described_class).to have_been_enqueued.once
      expect(WebsiteRebuild.count).to eq(1)
    end

    it "saute la fenêtre sur demande explicite" do
      described_class.request!(trigger: "api", immediate: true)

      expect(described_class).to have_been_enqueued.once
      expect(WebsiteRebuild.last.trigger).to eq("api")
    end

    it "ne diffère pas sous l'adaptateur inline (il ne sait pas) : exécute tout de suite sans planter" do
      previous = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :inline
      expect(described_class).not_to receive(:post)
      expect { described_class.request! }.not_to raise_error
      expect(WebsiteRebuild.last.status).to eq("skipped")
    ensure
      ActiveJob::Base.queue_adapter = previous
    end
  end

  describe ".recover!" do
    it "relance au démarrage une demande restée en attente" do
      described_class.request!
      lose_enqueued_jobs!

      expect(described_class.recover!).to be(true)
      expect(described_class).to have_been_enqueued.once
    end

    it "ne fait rien sans demande en attente" do
      expect(described_class.recover!).to be(false)
      expect(described_class).not_to have_been_enqueued
    end
  end

  describe "#perform" do
    it "marque la demande « skipped » sans URL de webhook" do
      described_class.request!
      expect(described_class).not_to receive(:post)

      expect(described_class.new.perform).to eq(:skipped)
      expect(WebsiteRebuild.last).to have_attributes(status: "skipped")
      expect(WebsiteRebuild.last.error_message).to include("WEBSITE_REBUILD_WEBHOOK_URL")
    end

    it "n'appelle jamais le webhook hors production sans autorisation explicite" do
      ENV["WEBSITE_REBUILD_WEBHOOK_URL"] = "https://deploy.example.org/hook"
      described_class.request!
      expect(described_class).not_to receive(:post)

      expect(described_class.new.perform).to eq(:skipped)
    end

    it "appelle le webhook une seule fois et trace la réponse" do
      enable_webhook!
      described_class.request!
      described_class.request!
      expect(described_class).to receive(:post).with("https://deploy.example.org/hook").once.and_return(response)

      expect(described_class.new.perform).to eq("200")
      expect(described_class.new.perform).to eq(:nothing_pending)
      expect(WebsiteRebuild.last).to have_attributes(status: "sent", response_code: "200", requests_count: 2)
      expect(WebsiteRebuild.last.dispatched_at).to be_present
    end

    it "trace un échec réseau sans lever" do
      enable_webhook!
      described_class.request!
      allow(described_class).to receive(:post).and_raise(SocketError, "getaddrinfo")

      expect(described_class.new.perform).to eq(:failed)
      expect(WebsiteRebuild.last).to have_attributes(status: "failed")
      expect(WebsiteRebuild.last.error_message).to include("getaddrinfo")
    end

    it "trace une réponse d'erreur" do
      enable_webhook!
      described_class.request!
      allow(described_class).to receive(:post).and_return(response("500"))

      described_class.new.perform
      expect(WebsiteRebuild.last).to have_attributes(status: "failed", response_code: "500")
    end
  end
end
