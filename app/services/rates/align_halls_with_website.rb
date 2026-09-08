module Rates
  # Réaligne les lignes `rates` des salles sur la page tarifs du site
  # (epic #234, phase 2 — décision 3 : le site est la source de vérité).
  #
  # La règle est stricte et idempotente : une ligne n'est corrigée QUE si elle
  # porte encore l'ancienne valeur de repli du catalogue. Un montant modifié à
  # la main dans Paramètres > Tarifs est laissé tel quel et signalé — c'est un
  # arbitrage humain, pas une erreur à écraser.
  #
  # Les clés de forfaits multi-jours introduites par la phase 2 sont créées si
  # elles manquent, avec le montant du site.
  #
  #   bin/rails rates:align_halls_with_website          # dry-run
  #   bin/rails rates:align_halls_with_website APPLY=1  # écrit
  class AlignHallsWithWebsite
    # Anciennes valeurs de repli, celles semées avant la phase 2. Une ligne qui
    # porte encore exactement ce montant n'a jamais été touchée par l'équipe.
    LEGACY_AMOUNTS = {
      "hall.grande_salle.journee_et_soiree"         => 38_000, # 380 € → 350 €
      "hall.petite_salle.journee_et_soiree"         => 20_000, # 200 € → 170 €
      "hall.cuisine_pro.journee_et_soiree"          => 14_000, # 140 € → 110 €
      "hall.deux_salles.journee_et_soiree"          => 54_000, # 540 € → 480 €
      "hall_weekend.grande_salle.journee_et_soiree" => 47_000, # 470 € → 455 €
      "hall_weekend.petite_salle.journee_et_soiree" => 25_000, # 250 € → 230 €
      "hall_weekend.cuisine_pro.journee_et_soiree"  => 18_000, # 180 € → 150 €
      "hall_weekend.deux_salles.journee_et_soiree"  => 64_500  # 645 € → 610 €
    }.freeze

    Result = Struct.new(:created, :realigned, :kept, :already_aligned, keyword_init: true) do
      def to_s
        "#{created.size} créées, #{realigned.size} réalignées, " \
          "#{kept.size} conservées (éditées à la main), #{already_aligned.size} déjà à jour"
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def run
      result = Result.new(created: [], realigned: [], kept: [], already_aligned: [])

      catalog_entries.each { |entry| apply(entry, result) }

      Pricing::Rates.reset! unless @dry_run
      result
    end

    private

    # Toutes les clés de salles du seed, avec leur montant courant du catalogue.
    def catalog_entries
      Rates::SeedFromCatalog.new.entries.select { |e| e[:key].start_with?("hall.", "hall_weekend.") }
    end

    def apply(entry, result)
      rate = Rate.find_by(key: entry[:key])

      if rate.nil?
        Rate.create!(entry) unless @dry_run
        result.created << "#{entry[:key]} = #{euros(entry[:amount_cents])}"
      elsif rate.amount_cents == entry[:amount_cents]
        result.already_aligned << entry[:key]
      elsif rate.amount_cents == LEGACY_AMOUNTS[entry[:key]]
        was = rate.amount_cents
        rate.update!(amount_cents: entry[:amount_cents], label: entry[:label]) unless @dry_run
        result.realigned << "#{entry[:key]} : #{euros(was)} → #{euros(entry[:amount_cents])}"
      else
        result.kept << "#{entry[:key]} : #{euros(rate.amount_cents)} en base, " \
                       "#{euros(entry[:amount_cents])} sur le site"
      end
    end

    def euros(cents) = format("%.2f €", cents.to_i / 100.0)
  end
end
