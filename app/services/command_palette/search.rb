module CommandPalette
  # Ce que la palette ⌘K trouve dans les données (redesign, Michael
  # 2026-10-29) : des séjours, des personnes (clients et membres) et des pages
  # du Guide, chacun dans la limite de ce que la personne peut lire. Les écrans
  # et les actions, qui dépendent des chemins et des droits de la vue, sont
  # filtrés par `CommandPaletteHelper`.
  #
  # Les recherches sont celles des écrans : `Stays::Search` (client, groupe,
  # notes, numéro « #718 »), `Customer.search` (nom, email, téléphone),
  # `GuidePage.search`. La palette n'invente pas sa propre façon de chercher.
  class Search
    LIMIT = 5
    MIN_LENGTH = Stays::Search::MIN_LENGTH

    attr_reader :query

    def initialize(user:, query:)
      @user = user
      @query = query.to_s.strip.first(80)
    end

    def searching? = @query.length >= MIN_LENGTH || stay_id.present?

    def stays
      return Stay.none unless searching? && @user.can_read?(:full)

      @stays ||= begin
        scope = stay_id ? Stay.where(id: stay_id) : Stays::Search.new(Stay.all, @query).call
        scope.includes(:customer, stay_items: :bookable)
             .order(Arel.sql("stays.arrival_date DESC NULLS LAST"), id: :desc).limit(LIMIT).to_a
      end
    end

    def customers
      return [] unless searching? && @query.length >= MIN_LENGTH && @user.can_read?(:full)

      @customers ||= Customer.search(@query).with_stay_counts.order(:first_name, :last_name).limit(LIMIT).to_a
    end

    def humans
      return [] unless searching? && @query.length >= MIN_LENGTH && @user.can_read?(:full)

      @humans ||= Human.where("humans.name ILIKE ?", "%#{Human.sanitize_sql_like(@query)}%").order(:name).limit(LIMIT).to_a
    end

    def guide_pages
      return [] unless searching? && @query.length >= MIN_LENGTH

      @guide_pages ||= GuidePage.readable_by(@user).search(@query).includes(:chapter).order(:title).limit(LIMIT).to_a
    end

    private

    def stay_id
      return @stay_id if defined?(@stay_id)

      @stay_id = Stays::Search.stay_id(@query)
    end
  end
end
