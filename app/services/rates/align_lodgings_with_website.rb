module Rates
  # Aligne les lignes `rates` des GÎTES sur la page tarifs du site
  # (epic #260, phase 1 — le site est la source de vérité).
  #
  # Deux gestes, dans le même passage :
  #
  #   1. les cinq briques du nouveau barème sont CRÉÉES si elles manquent ;
  #   2. les anciennes clés `first_night` / `extra_night` / `package_N` des trois
  #      gîtes sont NEUTRALISÉES — elles ne sont plus lues par le devis, les
  #      laisser en base ne ferait qu'une liste trompeuse dans Paramètres >
  #      Tarifs. Une ligne éditée à la main n'est jamais retirée en silence :
  #      elle est signalée, et c'est un humain qui tranche.
  #
  # Même règle que `Rates::AlignHallsWithWebsite` : on ne touche à une ligne
  # existante que si elle porte encore la valeur de repli d'origine.
  #
  #   bin/rails rates:align_lodgings_with_website          # dry-run
  #   bin/rails rates:align_lodgings_with_website APPLY=1  # écrit
  class AlignLodgingsWithWebsite
    Result = Struct.new(:created, :removed, :kept, :already_aligned, keyword_init: true) do
      def to_s
        "#{created.size} créées, #{removed.size} anciennes clés retirées, " \
          "#{kept.size} conservées (éditées à la main), #{already_aligned.size} déjà à jour"
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def run
      result = Result.new(created: [], removed: [], kept: [], already_aligned: [])

      new_entries.each { |entry| create_or_check(entry, result) }
      legacy_rates.each { |rate| retire(rate, result) }

      Pricing::Rates.reset! unless @dry_run
      result
    end

    private

    # Les cinq briques par gîte, au montant du site.
    def new_entries
      Rates::SeedFromCatalog.new.entries.select do |entry|
        Pricing::Catalog::LODGING_SITE_RATES.keys.any? do |name|
          Pricing::Catalog::LODGING_BRICK_LABELS.keys.any? do |brick|
            entry[:key] == Pricing::Catalog.lodging_brick_key(name, brick)
          end
        end
      end
    end

    # Les anciennes clés des TROIS gîtes du site. La Tiny house garde les
    # siennes : c'est toujours par elles qu'elle se tarifie.
    def legacy_rates
      keys = Pricing::Catalog::LODGING_SITE_RATES.keys.flat_map do |name|
        slug = Pricing::Catalog.lodging_key(name)
        Rate.where("key LIKE ?", "lodging.#{slug}.%").pluck(:key)
      end
      obsolete = keys.reject { |key| new_entries.any? { |entry| entry[:key] == key } }

      Rate.where(key: obsolete)
    end

    def create_or_check(entry, result)
      rate = Rate.find_by(key: entry[:key])

      if rate.nil?
        Rate.create!(entry) unless @dry_run
        result.created << "#{entry[:key]} = #{euros(entry[:amount_cents])}"
      elsif rate.amount_cents == entry[:amount_cents]
        result.already_aligned << entry[:key]
      else
        result.kept << "#{entry[:key]} : #{euros(rate.amount_cents)} en base, " \
                       "#{euros(entry[:amount_cents])} sur le site"
      end
    end

    # Une ancienne clé n'est retirée que si elle porte ENCORE la valeur du
    # catalogue historique — sinon quelqu'un l'a éditée et on le dit.
    def retire(rate, result)
      if legacy_fallback_cents(rate.key) == rate.amount_cents
        rate.destroy! unless @dry_run
        result.removed << "#{rate.key} (#{euros(rate.amount_cents)}) — clé morte, plus lue par le devis"
      else
        result.kept << "#{rate.key} : #{euros(rate.amount_cents)} en base, éditée à la main — " \
                       "clé morte, à retirer à la main"
      end
    end

    # Montant qu'aurait semé l'ancien catalogue pour cette clé, ou nil.
    def legacy_fallback_cents(key)
      @legacy_fallbacks ||= Pricing::Catalog::LODGING_RATES.flat_map { |name, rate|
        slug = Pricing::Catalog.lodging_key(name)
        [["lodging.#{slug}.first_night", rate.first_night_cents],
         ["lodging.#{slug}.extra_night", rate.extra_night_cents]] +
          rate.named_packages.map { |nights, package| ["lodging.#{slug}.package_#{nights}", package[:amount_cents]] }
      }.to_h

      @legacy_fallbacks[key]
    end

    def euros(cents) = format("%.2f €", cents.to_i / 100.0)
  end
end
