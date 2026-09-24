# Les gîtes et salles qu'on peut relier à un objet de la carte (epic #348,
# phase 3).
#
# Les gîtes COMPOSITES (le Grand-Duc) n'en font pas partie : leurs chambres sont
# celles de leurs composantes (la Hulotte et la Chevêche), dont le tracé porte
# déjà l'occupation. Les tracer aussi superposerait deux polygones pour les
# mêmes lits.
module Maps
  module Venues
    module_function

    def lodgings
      Lodging.where.not(id: LodgingComposition.select(:composite_lodging_id)).order(:id)
    end

    def spaces
      Space.all
    end

    def untraced_lodgings
      lodgings.where.not(id: traced_ids("Lodging"))
    end

    def untraced_spaces
      spaces.where.not(id: traced_ids("Space"))
    end

    # Les choix du sélecteur de la fiche : ce qui n'est pas encore tracé, plus
    # ce que l'objet affiché représente déjà.
    def options_for(feature)
      lodging_options = lodgings.reject { |l| traced?("Lodging", l.id, feature) }.map { |l| [l.name, "Lodging:#{l.id}"] }
      space_options = spaces.reject { |s| traced?("Space", s.id, feature) }.map { |s| [s.name, "Space:#{s.id}"] }
      { "Gîtes" => lodging_options, "Salles et espaces" => space_options }
    end

    def traced_ids(type)
      MapFeature.where(linked_type: type).where.not(linked_id: nil).select(:linked_id)
    end

    def traced?(type, id, feature)
      scope = MapFeature.where(linked_type: type, linked_id: id)
      scope = scope.where.not(id: feature.id) if feature.persisted?
      scope.exists?
    end
  end
end
