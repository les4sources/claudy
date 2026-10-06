module Mcp
  module Tools
    module Collectif
      # L'ordre du jour d'un rassemblement (AgendaItemsController et
      # AgendaItemNotesController) : ajouter, modifier, marquer traité,
      # déplacer au rassemblement suivant, supprimer, noter en réunion.
      class PointOdj < Ecriture
        include Commun

        GESTES = %w[ajouter modifier traiter rouvrir deplacer supprimer noter].freeze

        tool "point_odj",
             title: "Point de l'ordre du jour",
             description: "Agit sur l'ordre du jour d'un rassemblement : ajouter un point (titre, description, liste " \
                          "informations/triage/décisions/atelier, porteur ; tu en es l'auteur), le modifier, le marquer " \
                          "traité ou le rouvrir, le déplacer vers un autre rassemblement de la même catégorie, le " \
                          "supprimer, ou noter ce qui s'est dit en réunion (note vide = note effacée).",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 rassemblement: RASSEMBLEMENT.merge(description: "Pour ajouter : le rassemblement. Pour noter : celui où la note est prise (défaut : celui du point)."),
                 point: { type: %w[integer string], description: "Identifiant du point (#88), rendu par fiche_rassemblement." },
                 titre: { type: "string" },
                 description: TEXTE,
                 liste: { type: "string", enum: AgendaItem.lists.keys, description: "informations, triage, decisions ou atelier (défaut)." },
                 porteur: MEMBRE.merge(description: "Qui porte le point (nom, « moi », ou « aucun »)."),
                 vers: RASSEMBLEMENT.merge(description: "Pour déplacer : le rassemblement d'arrivée."),
                 note: TEXTE.merge(description: "Pour noter : le texte de la note de réunion.")
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.join(', ')}." unless GESTES.include?(geste)
          return plan_ajout(arguments) if geste == "ajouter"

          point = point!(arguments["point"])
          resume, donnees = send("plan_#{geste}", point, arguments)
          Plan.new(resume: "#{ligne_point(point)}\n#{resume}", empreinte: [etat_de(point), signature(arguments)],
                   donnees: donnees.merge(geste: geste, id: point.id))
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "ajouter"
            gathering = Gathering.find(d[:rassemblement])
            service = AgendaItems::CreateService.new(gathering: gathering, author: moi!)
            service! { service.run!(ActionController::Parameters.new(agenda_item: d[:attributs])) }
            "Point ajouté : #{ligne_point(service.agenda_item)}"
          when "modifier", "traiter", "rouvrir"
            point = AgendaItem.find(d[:id])
            point.update!(d[:attributs])
            "Point enregistré : #{ligne_point(point)}"
          when "deplacer"
            point = AgendaItem.find(d[:id])
            cible = Gathering.find(d[:vers])
            point.update!(gathering_id: cible.id, position: (cible.agenda_items.maximum(:position) || -1) + 1)
            "Point déplacé vers #{ligne_rassemblement(cible)}."
          when "supprimer"
            AgendaItem.find(d[:id]).soft_delete!(validate: false)
            "Point ##{d[:id]} supprimé (suppression douce)."
          when "noter"
            note = AgendaItemNote.find_or_initialize_by(agenda_item_id: d[:id], gathering_id: d[:rassemblement])
            if d[:texte].blank?
              note.destroy! if note.persisted?
              "Note de réunion effacée."
            else
              note.update!(body: html(d[:texte]))
              "Note de réunion enregistrée."
            end
          end
        rescue ActiveRecord::RecordInvalid => e
          raise Error, e.record.errors.full_messages.to_sentence
        end

        def plan_ajout(arguments)
          gathering = rassemblement!(arguments["rassemblement"].presence || raise(Error, "Donne le rassemblement."))
          titre = arguments["titre"].to_s.strip
          raise Error, "Donne le titre du point." if titre.empty?

          auteur = moi!
          attributs = attributs_point(arguments).merge(title: titre)
          attributs[:list] ||= "atelier"
          resume = "Ajouter à #{ligne_rassemblement(gathering)}\nPoint « #{titre} » · liste #{AgendaItem.list_label(attributs[:list])} · " \
                   "auteur #{auteur.name}#{" · porté par #{Human.find(attributs[:carrier_id]).name}" if attributs[:carrier_id].present?}"
          Plan.new(resume: resume, empreinte: [etat_de(gathering), signature(arguments)],
                   donnees: { geste: "ajouter", rassemblement: gathering.id, attributs: attributs })
        end

        def plan_modifier(point, arguments)
          attributs = attributs_point(arguments)
          attributs[:title] = arguments["titre"].to_s.strip if arguments["titre"].present?
          raise Error, "Rien à changer : titre, description, liste ou porteur." if attributs.empty?

          changes = attributs.map { |cle, valeur| "#{cle} → #{cle == :carrier_id ? (valeur.present? ? Human.find(valeur).name : 'personne') : valeur.to_s.truncate(80)}" }
          ["Modifier : #{changes.join(' · ')}", { attributs: attributs }]
        end

        def plan_traiter(point, _arguments)
          raise Error, "Ce point est déjà traité." if point.completed?

          ["Marquer TRAITÉ.", { attributs: { completed: true } }]
        end

        def plan_rouvrir(point, _arguments)
          raise Error, "Ce point n'est pas traité." unless point.completed?

          ["Rouvrir le point.", { attributs: { completed: false } }]
        end

        def plan_deplacer(point, arguments)
          raise Error, "Donne le rassemblement d'arrivée (vers)." if arguments["vers"].blank?

          cible = rassemblement!(arguments["vers"])
          raise Error, "Le point est déjà dans ce rassemblement." if cible.id == point.gathering_id
          if cible.gathering_category_id != point.gathering.gathering_category_id
            raise Error, "Un point ne se déplace que vers un rassemblement de la même catégorie (#{point.gathering.gathering_category&.name})."
          end

          ["Déplacer vers #{ligne_rassemblement(cible)}. Les notes déjà prises restent sur l'ancien rassemblement.", { vers: cible.id }]
        end

        def plan_supprimer(point, _arguments)
          motif!({ "motif" => @motif })
          decisions = point.decisions.count
          ["SUPPRIMER ce point#{" ; #{decisions} décision(s) y restent au registre, détachées" if decisions.positive?}.", {}]
        end

        def plan_noter(point, arguments)
          gathering = arguments["rassemblement"].present? ? rassemblement!(arguments["rassemblement"]) : point.gathering
          texte = arguments["note"].to_s
          actuelle = AgendaItemNote.find_by(agenda_item_id: point.id, gathering_id: gathering.id)
          resume = if texte.strip.empty?
                     raise Error, "Il n'y a pas de note à effacer." unless actuelle

                     "Effacer la note de réunion."
                   else
                     "#{actuelle ? 'Remplacer' : 'Écrire'} la note de réunion (#{nom_rassemblement(gathering)}) :\n#{texte.strip}"
                   end
          [resume, { rassemblement: gathering.id, texte: texte.strip }]
        end

        def attributs_point(arguments)
          attributs = {}
          attributs[:description] = html(arguments["description"]) if arguments.key?("description")
          if arguments["liste"].present?
            raise Error, "liste : #{AgendaItem.lists.keys.join(', ')}." unless AgendaItem.lists.key?(arguments["liste"])

            attributs[:list] = arguments["liste"]
          end
          if arguments["porteur"].present?
            attributs[:carrier_id] = arguments["porteur"].to_s.strip.match?(/\A(aucun|personne)\z/i) ? nil : membre!(arguments["porteur"]).id
          end
          attributs
        end

        def point!(reference)
          raise Error, "Donne le point (identifiant)." if reference.blank?

          AgendaItem.includes(:author, :carrier, gathering: :gathering_category).find_by(id: id!(reference, "point")) ||
            raise(Error, "Aucun point d'ordre du jour ##{reference.to_s.delete('#')}.")
        end

        def ligne_point(point)
          "Point ##{point.id} « #{point.title} » (#{AgendaItem.list_label(point.list)}#{', traité' if point.completed?}) " \
            "· rassemblement ##{point.gathering_id}"
        end
      end
    end
  end
end
