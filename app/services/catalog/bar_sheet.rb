module Catalog
  # La fiche du bar à imprimer pour un mois (Michael, 2026-11-01) : la feuille
  # posée au bar, sur laquelle chaque compte sourcier coche ses consommations,
  # puis qu'on encode dans Fiches papier.
  #
  # Mêmes règles que l'écran d'encodage, pour que le papier et l'écran se
  # répondent ligne pour ligne :
  # - articles ACTIFS du canal Bar, groupés par catégorie ;
  # - une colonne par compte sourcier actif (`MemberAccount`) ;
  # - prix SOURCIER à la date d'encodage de la fiche (`PaperSheet#entry_date`,
  #   fin du mois) : ce qui est imprimé est ce qui sera compté.
  class BarSheet
    CHANNEL = "bar".freeze

    # L'ordre de l'ancienne fiche : on cherche une bière avant un paquet de
    # chips. Une catégorie inconnue vient ensuite, par ordre alphabétique ; les
    # articles sans catégorie ferment la fiche.
    CATEGORY_ORDER = %w[bière vin soft snack café].freeze

    # Repère visuel par catégorie, comme les catégories de la carte du bar du
    # Design System des 4 Sources (un emoji en tête, une couleur de pôle en
    # aplat clair, une seule à la fois).
    CATEGORY_LOOKS = [
      { match: "bière", emoji: "🍺", tone: "socioculturel" },
      { match: "vin", emoji: "🍷", tone: "accueil" },
      { match: "soft", emoji: "🧃", tone: "ressourcement" },
      { match: "snack", emoji: "🥨", tone: "vie-collective" },
      { match: "café", emoji: "☕", tone: "artisanat" }
    ].freeze
    FALLBACK_TONES = %w[nature microferme artisanat].freeze

    Group = Struct.new(:name, :emoji, :tone, :lines, keyword_init: true)
    Line = Struct.new(:item, :price_cents, keyword_init: true)

    attr_reader :month

    def self.parse_month(raw)
      Date.strptime(raw.to_s, "%Y-%m").beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    def initialize(month: Date.current)
      @month = month.to_date.beginning_of_month
    end

    def price_date = month.end_of_month

    def accounts
      # Trié sans tenir compte des accents : « Émilie » parmi les E, pas après
      # « Seb & Mag » comme le ferait l'ordre de la base.
      @accounts ||= MemberAccount.where(active: true).to_a.sort_by { |account| normalized(account.name) }
    end

    def groups
      @groups ||= build_groups
    end

    def empty? = groups.empty?

    def missing_prices
      groups.flat_map(&:lines).reject(&:price_cents).map(&:item)
    end

    private

    def items
      CatalogItem.active.for_channel(CHANNEL).includes(:catalog_prices).order(:name).to_a
    end

    def build_groups
      grouped = items.group_by { |item| item.category.to_s.strip.presence }
      fallback = 0

      grouped.sort_by { |name, _| sort_key(name) }.map do |name, category_items|
        look = look_for(name)
        tone = look&.fetch(:tone) || (FALLBACK_TONES[fallback % FALLBACK_TONES.size].tap { fallback += 1 })

        Group.new(
          name: name || "Autres",
          emoji: look&.fetch(:emoji),
          tone: tone,
          lines: category_items.map { |item| Line.new(item: item, price_cents: item.price_on(price_date)&.member_price_cents) }
        )
      end
    end

    def sort_key(name)
      return [2, ""] if name.nil?

      rank = CATEGORY_ORDER.index { |key| normalized(name).include?(normalized(key)) }
      rank ? [0, rank.to_s.rjust(3, "0")] : [1, normalized(name)]
    end

    def look_for(name)
      return nil if name.nil?

      CATEGORY_LOOKS.find { |look| normalized(name).include?(normalized(look[:match])) }
    end

    def normalized(text) = I18n.transliterate(text.to_s).downcase
  end
end
