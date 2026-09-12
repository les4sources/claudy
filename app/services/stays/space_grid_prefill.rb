module Stays
  # Préremplissage de la grille ESPACES d'un draft (epic #234).
  #
  # `Stays::DraftReconstructor` rend les espaces d'un séjour sous forme de lignes
  # `halls` ({kind, date, period}) ; la grille jours × espaces, elle, lit
  # `space_slots` ({kind => [période par jour]}). Sans cette conversion, un
  # formulaire prérempli rend une grille VIDE — et une soumission efface alors
  # les salles du séjour sans rien dire.
  #
  # Le code vivait en privé dans `StaysController` : l'admin préremplissait, la
  # modification client (`public/stay_change_requests#new`) non. C'était le même
  # partial des deux côtés, mais pas les mêmes données (epic #234, phase 3).
  #
  # Les deux représentations ne coexistent jamais : quand la grille prend le
  # relais, `halls` est vidé — sinon le devis compterait les salles deux fois.
  module SpaceGridPrefill
    module_function

    # Applique la conversion sur place. Idempotent : ne fait rien si la grille
    # n'est pas active (pas de jours), si le draft porte déjà des `space_slots`
    # (re-render d'un POST de la grille) ou s'il n'a aucune ligne `halls`.
    def apply!(draft, days)
      return if draft.nil? || days.blank?
      return if Array(draft.space_slots&.values).flatten.any?(&:present?)
      return if Array(draft.halls).blank?

      draft.space_slots = call(draft.halls, days)
      draft.halls = []
    end

    # Lignes `halls` → grille `space_slots`, indexée depuis le jour d'arrivée.
    # La fenêtre est [arrivée, départ], départ INCLUS (epic #234, phase 1) : une
    # salle réservée le jour du départ existe en base et doit se retrouver dans
    # la grille. Les lignes hors fenêtre ou sans date sont ignorées.
    def call(halls, days)
      arrival = days.first
      count   = days.size

      Array(halls).each_with_object({}) do |raw, slots|
        hall   = raw.respond_to?(:symbolize_keys) ? raw.symbolize_keys : raw
        key    = hall[:kind].to_s
        period = hall[:period].to_s
        date   = parse_date(hall[:date])
        next if key.blank? || period.blank? || date.nil?

        idx = (date - arrival).to_i
        next if idx.negative? || idx >= count

        (slots[key] ||= Array.new(count, ""))[idx] = period
      end
    end

    def parse_date(value)
      return value if value.is_a?(Date)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
