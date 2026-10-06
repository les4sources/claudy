module Mcp
  module Tools
    module Collectif
      # Le registre des décisions (DecisionsController#index et #show).
      class RegistreDecisions < Base
        include Commun

        tool "decisions",
             title: "Registre des décisions",
             description: "Cherche dans les décisions du collectif (titre, résumé, texte complet), les plus récentes " \
                          "d'abord. Avec `decision`, rend le texte complet d'une décision et ses commentaires.",
             schema: {
               properties: {
                 recherche: { type: "string", description: "Mots à chercher. Vide : les dernières décisions." },
                 decision: DECISION,
                 du: DATE, au: DATE
               }
             }

        LIMITE = 50

        def call(arguments)
          return fiche(decision!(arguments["decision"])) if arguments["decision"].present?

          scope = arguments["recherche"].present? ? Decision.search(arguments["recherche"]) : Decision.all
          du = date_ou_nil(arguments["du"], "du")
          au = date_ou_nil(arguments["au"], "au")
          scope = scope.where(taken_at: du..) if du
          scope = scope.where(taken_at: ..au) if au
          liste = scope.recent.limit(LIMITE).to_a
          return "Aucune décision." if liste.empty?

          "#{liste.size} décision(s) :\n#{liste.map { |d| ligne_decision(d) }.join("\n")}"
        end

        private

        def fiche(d)
          lignes = [ligne_decision(d), "Notée par #{d.recorded_by&.name}"]
          lignes << "Point de l'ordre du jour ##{d.agenda_item_id}" if d.agenda_item_id
          corps = texte_riche(d.body)
          lignes << "\n#{corps}" if corps.present?
          commentaires = d.comments.chronological.includes(:author).map do |c|
            "- #{I18n.l(c.created_at, format: '%d/%m %H:%M')} #{c.author&.human&.name || c.author&.email} : #{texte_riche(c.body)}"
          end
          lignes << "\nCommentaires :\n#{commentaires.join("\n")}" if commentaires.any?
          lignes.join("\n")
        end
      end
    end
  end
end
