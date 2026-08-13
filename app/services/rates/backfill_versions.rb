module Rates
  # Donne une première version datée à chaque tarif qui n'en a pas encore
  # (issue #156). Sans ça, `Pricing::Rates.cents(key, on:)` répondrait `nil`
  # partout et la reprise d'historique (phase 7) n'aurait rien à lire.
  #
  # La version créée porte le montant COURANT, ouverte depuis
  # `RateVersion::ORIGIN` et sans fin : le barème d'aujourd'hui est réputé avoir
  # toujours été celui-là, faute de mieux. Aucun montant n'est modifié.
  #
  # Idempotent : un tarif qui a déjà au moins une version est laissé tel quel.
  class BackfillVersions
    Result = Struct.new(:created, :skipped, :dry_run, keyword_init: true) do
      def to_s
        prefix = dry_run ? "[dry-run] " : ""
        verb = dry_run ? "à créer" : "créées"
        "#{prefix}#{created} version(s) #{verb}, #{skipped} tarif(s) déjà versionné(s)"
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def run
      result = Result.new(created: 0, skipped: 0, dry_run: @dry_run)

      Rate.ordered.includes(:rate_versions).each do |rate|
        if rate.rate_versions.any?
          result.skipped += 1
          next
        end

        create_origin_version(rate) unless @dry_run
        result.created += 1
      end

      Pricing::Rates.reset! unless @dry_run
      result
    end

    private

    def create_origin_version(rate)
      rate.rate_versions.create!(
        amount_cents: rate.amount_cents,
        active_from: RateVersion::ORIGIN,
        note: "Reprise du montant courant (#156)"
      )
    end
  end
end
