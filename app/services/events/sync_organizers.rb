module Events
  # Aligne les organisateurs d'un événement sur ce que le formulaire a coché
  # (epic #245, phase 1).
  #
  # Le formulaire envoie une ligne par humain :
  #
  #   organizers: { "12" => { "selected" => "1", "weight" => "2" }, "13" => { ... } }
  #
  # On ne supprime-recrée pas aveuglément : un organisateur déjà en place garde
  # sa ligne (et son historique PaperTrail), seul son poids bouge. Ceux qui sont
  # décochés partent, ceux qui apparaissent arrivent.
  class SyncOrganizers
    def initialize(event:)
      @event = event
    end

    # `submitted` : le hash brut du formulaire, ou nil quand le formulaire ne
    # portait pas la section (auquel cas on ne touche à rien).
    def run(submitted)
      return if submitted.nil?

      wanted = normalize(submitted)
      existing = @event.event_organizers.index_by(&:human_id)

      (existing.keys - wanted.keys).each { |human_id| existing[human_id].destroy }

      wanted.each do |human_id, weight|
        organizer = existing[human_id]
        next @event.event_organizers.create(human_id: human_id, weight: weight) if organizer.nil?

        organizer.update(weight: weight) if organizer.weight != weight
      end
    end

    private

    # Ne retient que les lignes cochées, et ramène tout poids absent ou
    # inférieur à 1 à 1 — un poids nul ferait disparaître quelqu'un du partage
    # sans qu'il soit décoché, ce qui serait invisible à l'écran.
    def normalize(submitted)
      # `to_unsafe_h` sur des `ActionController::Parameters` non permis : rien
      # n'en sort tel quel — la clé devient un Integer et le poids un Integer
      # borné, donc aucune valeur brute n'atteint la base.
      raw = submitted.respond_to?(:to_unsafe_h) ? submitted.to_unsafe_h : submitted.to_h

      raw.filter_map do |human_id, attributes|
        next unless ActiveModel::Type::Boolean.new.cast(attributes["selected"])

        [human_id.to_i, [attributes["weight"].to_i, 1].max]
      end.to_h
    end
  end
end
