module Mcp
  module Tools
    module Carte
      # Les fils de commentaires de la carte (MapCommentsController) : poser un
      # point avec son premier message, répondre, résoudre, rouvrir, supprimer
      # son propre message.
      class FilCarte < Ecriture
        include Commun

        tool "fil_carte",
             title: "Fil de commentaires de la carte",
             description: "`ouvrir` un fil : un point (latitude, longitude) et son premier message. `repondre` à un fil, " \
                          "le `resoudre` ou le `rouvrir` (un `message` du fil, #id rendu par fils_carte). `supprimer` " \
                          "un de TES messages (le premier emporte tout le fil et son point ; motif obligatoire). Une " \
                          "réponse NOTIFIE les participants du fil, une résolution l'auteur du premier message (email " \
                          "s'ils l'ont demandé).",
             schema: {
               properties: {
                 geste: { type: "string", enum: %w[ouvrir repondre resoudre rouvrir supprimer] },
                 latitude: LATITUDE,
                 longitude: LONGITUDE,
                 message: { type: %w[integer string], description: "Un message du fil (#id)." },
                 texte: TEXTE
               },
               required: %w[geste]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          return plan_ouvrir(arguments) if geste == "ouvrir"
          raise Error, "geste : ouvrir, repondre, resoudre, rouvrir ou supprimer." unless %w[repondre resoudre rouvrir supprimer].include?(geste)

          message = MapComment.includes(:author, :map_feature).find_by(id: id!(arguments["message"], "message")) ||
                    raise(Error, "Aucun message ##{arguments['message'].to_s.delete('#')}.")
          racine = message.root
          contexte = "le fil ##{racine.id} (« #{racine.body.squish.truncate(80)} », #{racine.author.display_name})"
          resume = case geste
                   when "repondre"
                     texte = arguments["texte"].to_s.strip
                     raise Error, "Écris un message." if texte.empty?

                     notifies = racine.participants.to_a - [user]
                     "Répondre dans #{contexte} :\n« #{texte} »\nNotifié(s) : #{notifies.map(&:display_name).join(', ').presence || 'personne'}."
                   when "resoudre"
                     raise Error, "Ce fil est déjà résolu." if racine.resolved?

                     "Marquer résolu #{contexte}.#{" #{racine.author.display_name} est notifié(e)." unless racine.author == user}"
                   when "rouvrir"
                     raise Error, "Ce fil n'est pas résolu." unless racine.resolved?

                     "Rouvrir #{contexte}."
                   else
                     raise Error, "On ne supprime que ses propres messages : celui-ci est de #{message.author.display_name}." unless message.removable_by?(user)

                     motif!({ "motif" => @motif })
                     message.root? ? "SUPPRIMER tout #{contexte} et son point sur la carte." : "SUPPRIMER ta réponse ##{message.id} dans #{contexte}."
                   end
          Plan.new(resume: resume, empreinte: [etat_de(racine), etat_de(message), geste, arguments["texte"].to_s.strip],
                   donnees: { geste: geste, id: message.id, texte: arguments["texte"].to_s.strip })
        end

        def plan_ouvrir(arguments)
          lat, lng = coordonnees!(arguments["latitude"], arguments["longitude"])
          texte = arguments["texte"].to_s.strip
          raise Error, "Écris un premier message." if texte.empty?

          Plan.new(resume: "Poser un point de commentaire en (#{lat}, #{lng}) avec le message :\n« #{texte} »",
                   empreinte: [lat, lng, texte], donnees: { geste: "ouvrir", lat: lat, lng: lng, texte: texte })
        end

        def appliquer(plan)
          d = plan.donnees
          if d[:geste] == "ouvrir"
            point = MapLayer.for_kind(:comments).map_features.new(
              feature_kind: "comment", created_by: user, geometry: { "type" => "Point", "coordinates" => [d[:lng], d[:lat]] }
            )
            racine = point.map_comments.build(author: user, body: d[:texte])
            valide!(racine)
            point.save!
            return "Fil ##{racine.id} ouvert sur le point ##{point.id}."
          end

          message = MapComment.find(d[:id])
          case d[:geste]
          when "repondre"
            reponse = message.reply!(author: user, body: d[:texte])
            "Réponse ##{reponse.id} publiée dans le fil ##{reponse.root.id}."
          when "resoudre"
            message.resolve!(by: user)
            "Fil ##{message.root.id} résolu."
          when "rouvrir"
            message.reopen!
            "Fil ##{message.root.id} rouvert."
          else
            message.remove!
            message.root? ? "Fil ##{message.id} supprimé avec son point." : "Message ##{message.id} supprimé."
          end
        end
      end
    end
  end
end
