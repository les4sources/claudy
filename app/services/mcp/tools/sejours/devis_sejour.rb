module Mcp
  module Tools
    module Sejours
      # Le panneau « Devis » du formulaire Séjour, sans rien enregistrer.
      class DevisSejour < Base
        include Commun
        include Composition

        tool "devis_sejour",
             title: "Devis d'un séjour",
             description: "Calcule le prix d'une composition (gîte, dates, espaces, camping, repas, activités, draps) " \
                          "avec le barème de Claudy, et dit si le gîte est libre. N'enregistre rien.",
             schema: { properties: Composition::PROPRIETES, required: %w[arrivee depart] }

        def call(arguments)
          draft = brouillon(arguments)
          lignes = [lignes_devis(draft.quote)]
          if draft.lodging
            libre = Stays::LodgingAvailability.call(stay: nil, draft: draft)
            lignes << (libre ? "#{draft.lodging.name} est libre à ces dates." : "⚠ #{draft.lodging.name} n'est PAS libre à ces dates.")
          end
          lignes.join("\n")
        end
      end
    end
  end
end
