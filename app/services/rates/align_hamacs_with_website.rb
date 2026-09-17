module Rates
  # Aligne le prix des HAMACS sur la page tarifs du site (epic #260, phase 2,
  # décision 7 : « Location hamac/tarp/matelas isolant : 10 € »).
  #
  # Deux endroits portent un prix de hamac, et les deux sont lus par
  # `Pricing::Catalog.hamac_rate` dans cet ordre :
  #
  #   1. les lignes `rates` `hamac.simple` / `hamac.double` ;
  #   2. les `RentalItem` « Hamac simple » / « Hamac double » (objets physiques).
  #
  # Même règle que `Rates::AlignLodgingsWithWebsite` : on ne corrige une valeur
  # existante que si elle porte ENCORE le montant d'origine (750 / 1 500). Une
  # valeur éditée à la main est signalée, jamais écrasée — c'est un humain qui
  # tranche.
  #
  #   bin/rails rates:align_hamacs_with_website          # dry-run
  #   bin/rails rates:align_hamacs_with_website APPLY=1  # écrit
  class AlignHamacsWithWebsite
    Result = Struct.new(:created, :aligned, :kept, :already_aligned, keyword_init: true) do
      def to_s
        "#{created.size} créées, #{aligned.size} réalignées, " \
          "#{kept.size} conservées (éditées à la main), #{already_aligned.size} déjà à jour"
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def run
      result = Result.new(created: [], aligned: [], kept: [], already_aligned: [])

      Pricing::Catalog::HAMAC_FALLBACK_CENTS.each do |kind, target_cents|
        align_rate(kind, target_cents, result)
        align_rental_item(kind, target_cents, result)
      end

      Pricing::Rates.reset! unless @dry_run
      result
    end

    private

    def align_rate(kind, target_cents, result)
      key  = "hamac.#{kind}"
      rate = Rate.find_by(key: key)

      if rate.nil?
        unless @dry_run
          Rate.create!(key: key, amount_cents: target_cents, unit: "cents",
                       label: "Hamac #{kind} — €/nuit/unité")
        end
        result.created << "#{key} = #{euros(target_cents)}"
      elsif rate.amount_cents == target_cents
        result.already_aligned << key
      elsif rate.amount_cents == legacy_cents(kind)
        rate.update!(amount_cents: target_cents) unless @dry_run
        result.aligned << "#{key} : #{euros(legacy_cents(kind))} → #{euros(target_cents)}"
      else
        result.kept << "#{key} : #{euros(rate.amount_cents)} en base, " \
                       "#{euros(target_cents)} sur le site — éditée à la main, à trancher"
      end
    end

    # Le `RentalItem` est l'objet physique : on ne le crée JAMAIS ici (son stock
    # n'est pas notre affaire), on ne corrige que son prix quand il est d'origine.
    def align_rental_item(kind, target_cents, result)
      name = Pricing::Catalog::HAMAC_RENTAL_ITEM_NAMES.fetch(kind.to_s)
      item = RentalItem.find_by(name: name)
      return if item.nil?

      if item.price_cents == target_cents
        result.already_aligned << "RentalItem « #{name} »"
      elsif item.price_cents == legacy_cents(kind)
        item.update!(price_cents: target_cents) unless @dry_run
        result.aligned << "RentalItem « #{name} » : #{euros(legacy_cents(kind))} → #{euros(target_cents)}"
      else
        result.kept << "RentalItem « #{name} » : #{euros(item.price_cents)} en base, " \
                       "#{euros(target_cents)} sur le site — édité à la main, à trancher"
      end
    end

    def legacy_cents(kind) = Pricing::Catalog::HAMAC_LEGACY_CENTS[kind.to_s]

    def euros(cents) = format("%.2f €", cents.to_i / 100.0)
  end
end
