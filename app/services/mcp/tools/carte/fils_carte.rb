module Mcp
  module Tools
    module Carte
      # Les fils de commentaires de la carte (mode Commentaires) : un point,
      # un premier message, des réponses ; ouvert ou résolu.
      class FilsCarte < Base
        include Commun

        tool "fils_carte",
             title: "Fils de commentaires de la carte",
             description: "Les fils de commentaires posés sur la carte (« la clôture est cassée ici ») : point GPS, " \
                          "messages, auteur, ouvert ou résolu. Défaut : les fils ouverts. Un message (#id) se passe à " \
                          "fil_carte pour répondre, résoudre, rouvrir ou supprimer.",
             schema: {
               properties: {
                 statut: { type: "string", enum: %w[ouverts resolus tous], description: "Défaut : ouverts." },
                 recherche: { type: "string", description: "Texte cherché dans les messages." }
               }
             }

        def call(arguments)
          racines = MapComment.roots.joins(:map_feature).includes(:author, :map_feature).order(created_at: :desc)
          racines = case arguments["statut"].presence || "ouverts"
                    when "ouverts" then racines.where(resolved_at: nil)
                    when "resolus" then racines.where.not(resolved_at: nil)
                    else racines
                    end
          if arguments["recherche"].present?
            ids = ::Maps::Search.new(mode: "comments", query: arguments["recherche"]).feature_ids
            racines = racines.where(map_feature_id: ids)
          end
          racines = racines.limit(50).to_a
          return "Aucun fil." if racines.empty?

          racines.map do |racine|
            messages = racine.thread.map do |c|
              "  Message ##{c.id} #{I18n.l(c.created_at.to_date)} #{c.author.display_name} : #{c.body.squish.truncate(300)}"
            end
            "Fil ##{racine.id} #{racine.resolved? ? "résolu le #{I18n.l(racine.resolved_at.to_date)}" : 'ouvert'} · " \
              "point ##{racine.map_feature_id} #{point(racine.map_feature)}\n#{messages.join("\n")}"
          end.join("\n\n")
        end
      end
    end
  end
end
