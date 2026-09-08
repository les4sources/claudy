module Kitchen
  # La grille jours × services (issue #238, décision 1).
  #
  # On pose le type et les convives une fois, on coche des cases, et
  # l'enregistrement crée UNE LIGNE AUTONOME par case cochée. C'est de là que
  # découle tout le reste : une ligne restant l'unité de validation, la cuisine
  # peut se désister sur un seul service — « je prends la semaine, sauf le
  # mercredi midi » — sans qu'on ait rien à inventer.
  #
  # Cocher le goûter avec le type « Repas » crée une ligne de type `gouter` :
  # le goûter est un service facturable à part, avec son propre tarif.
  class GridSubmission
    Result = Struct.new(:orders, :error, keyword_init: true) do
      def success? = error.nil?
    end

    MOMENTS = %w[midi gouter soir].freeze

    # `cells` : { "2026-06-08" => { "midi" => "1", "soir" => "1" }, … }
    def initialize(stay:, attributes:, cells:)
      @stay = stay
      @attributes = attributes
      @cells = cells || {}
    end

    def run
      return Result.new(orders: [], error: "Choisis d'abord un séjour.") if @stay.blank?

      checked = checked_cells
      return Result.new(orders: [], error: "Coche au moins un service à préparer.") if checked.empty?

      orders = []
      MealOrder.transaction do
        orders = checked.map { |date, moment| build(date, moment) }
        orders.each(&:save!)
      end

      Result.new(orders: orders)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(orders: [], error: e.record.errors.full_messages.to_sentence)
    end

    private

    # [[Date, "midi"], …] dans l'ordre du séjour, pour que les lignes créées
    # suivent la chronologie.
    def checked_cells
      raw_cells.flat_map { |day, moments|
        date = parse_date(day)
        next [] if date.nil?

        MOMENTS.filter_map do |moment|
          [date, moment] if ActiveModel::Type::Boolean.new.cast(moments[moment])
        end
      }.sort_by { |date, moment| [date, MOMENTS.index(moment)] }
    end

    def raw_cells
      @cells.respond_to?(:to_unsafe_h) ? @cells.to_unsafe_h : @cells.to_h
    end

    def build(date, moment)
      @stay.meal_orders.new(
        @attributes.merge(
          kind: kind_for(moment),
          # Le moment du goûter vit dans son type ; le champ reste renseigné
          # pour que le tri et l'affichage par journée restent lisibles.
          moment: moment,
          date: date
        )
      )
    end

    # Le goûter n'existe que dans la famille `repas` : cocher son créneau avec
    # un buffet ou un apéro n'a pas de sens, et la grille ne le propose pas.
    def kind_for(moment)
      return "gouter" if moment == "gouter" && @attributes[:kind].to_s == "repas"

      @attributes[:kind]
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
