module Kitchen
  # La saisie de cuisine : UN séjour, N prestations, une transaction (issues #238
  # et #265).
  #
  # Deux règles tiennent tout le reste.
  #
  # PREMIÈRE : une case cochée = une ligne autonome. La ligne restant l'unité de
  # validation, la cuisine peut se désister sur un seul service — « je prends la
  # semaine, sauf le mercredi midi » — sans qu'on ait rien à inventer.
  #
  # SECONDE (issue #265) : le séjour est la SEULE chose partagée. Un même
  # enregistrement peut porter l'apéro du vendredi, le buffet du samedi et les
  # repas du dimanche — chacun avec son type, ses convives, son prix, son
  # responsable et son statut client. On ne crée aucun objet « demande » entre le
  # séjour et les lignes : le regroupement par séjour existe déjà à l'affichage,
  # et PaperTrail garde la trace de qui a ajouté quoi.
  #
  # Cocher le goûter avec le type « Repas » crée une ligne de type `gouter` :
  # le goûter est un service facturable à part, avec son propre tarif.
  class GridSubmission
    Result = Struct.new(:orders, :error, keyword_init: true) do
      def success? = error.nil?
    end

    # Un bloc de prestation du formulaire. `attributes` porte ce qui vaut pour
    # toutes ses lignes (type, convives, prix, responsable, statut, précisions,
    # et — sans grille — la date et le moment uniques) ; `cells` porte les cases
    # cochées de sa grille.
    Block = Struct.new(:index, :attributes, :cells, keyword_init: true) do
      def label = "Prestation #{index.to_i + 1}"
      def value(key) = attributes[key.to_sym]
      def cells_hash = cells.respond_to?(:to_unsafe_h) ? cells.to_unsafe_h : (cells || {}).to_h
    end

    MOMENTS = %w[midi gouter soir].freeze

    def initialize(stay:, blocks:)
      @stay = stay
      @blocks = Array(blocks)
    end

    def run
      return Result.new(orders: [], error: "Choisis d'abord un séjour.") if @stay.blank?
      return Result.new(orders: [], error: "Ajoute au moins une prestation.") if @blocks.empty?

      pairs = []
      @blocks.each do |block|
        lines = lines_for(block)
        if lines.empty?
          return Result.new(orders: [],
                            error: "#{block.label} : coche au moins un service à préparer.")
        end

        pairs.concat(lines.map { |line| [block, line] })
      end

      MealOrder.transaction { pairs.each { |(_, order)| order.save! } }

      orders = pairs.map(&:last)
      # APRÈS le commit, jamais dedans : une saisie qui échoue n'envoie rien.
      # Les callbacks de ligne se sont tus (`skip_notifications`), c'est ici que
      # part l'email — un seul par destinataire (issue #266).
      Kitchen::GroupedNotifier.new(orders: orders).call

      Result.new(orders: orders)
    rescue ActiveRecord::RecordInvalid => e
      faulty = pairs.find { |(_, order)| order.equal?(e.record) }&.first
      message = e.record.errors.full_messages.to_sentence
      Result.new(orders: [], error: faulty ? "#{faulty.label} : #{message}" : message)
    end

    private

    # Une grille cochée donne N lignes ; un bloc sans grille (séjour dont les
    # dates manquent) retombe sur la saisie d'un service unique.
    def lines_for(block)
      checked = checked_cells(block)
      return checked.map { |date, moment| build(block, date, moment) } if checked.any?
      return [] if block.value(:date).blank?

      [build(block, parse_date(block.value(:date)), block.value(:moment))]
    end

    # [[Date, "midi"], …] dans l'ordre du séjour, pour que les lignes créées
    # suivent la chronologie.
    def checked_cells(block)
      block.cells_hash.flat_map { |day, moments|
        date = parse_date(day)
        next [] if date.nil?

        MOMENTS.filter_map do |moment|
          [date, moment] if ActiveModel::Type::Boolean.new.cast(moments[moment])
        end
      }.sort_by { |date, moment| [date, MOMENTS.index(moment)] }
    end

    def build(block, date, moment)
      # La ligne ne prévient plus la cuisine toute seule : c'est la SAISIE qui
      # prévient, une fois entière et commitée (issue #266).
      order = @stay.meal_orders.new(
        block.attributes.except(:date, :moment).merge(
          kind: kind_for(block, moment),
          # Le moment du goûter vit dans son type ; le champ reste renseigné
          # pour que le tri et l'affichage par journée restent lisibles.
          moment: moment,
          date: date
        )
      )
      order.skip_notifications = true
      order
    end

    # Le goûter n'existe que dans la famille `repas` : cocher son créneau avec
    # un buffet ou un apéro n'a pas de sens, et la grille ne le propose pas.
    def kind_for(block, moment)
      return "gouter" if moment == "gouter" && block.value(:kind).to_s == "repas"

      block.value(:kind)
    end

    def parse_date(value)
      return value if value.is_a?(Date)

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
