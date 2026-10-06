module Mcp
  module Tools
    module Carte
      # Les tâches de gestion d'une plante ou d'un objet de la carte
      # (MapTasksController#create, #update, #destroy) : ce qui revient
      # chaque année, rangé par mois dans le carnet.
      class TacheCarte < Ecriture
        include Commun

        tool "tache_carte",
             title: "Tâche de gestion de la carte",
             description: "`ajouter` une tâche annuelle (« Fauche des orties », juin et septembre) à une `plante` ou à un " \
                          "`element` de la carte ; `modifier` ou `supprimer` (motif obligatoire) une `tache` existante " \
                          "(#id, rendu par carnet_taches ou les fiches). Filière par défaut : nourricier pour une plante, " \
                          "terrain pour un objet.",
             schema: {
               properties: {
                 geste: { type: "string", enum: %w[ajouter modifier supprimer] },
                 plante: PLANTE,
                 element: ELEMENT,
                 tache: { type: %w[integer string], description: "La tâche (#id), pour modifier ou supprimer." },
                 libelle: TEXTE,
                 filiere: { type: "string", enum: MapTask::SECTORS.keys },
                 frequence: { type: "string", description: "Texte libre (« tous les 3 ans »)." },
                 mois: MOIS.merge(description: "Les mois où elle revient. Donné, il REMPLACE la liste."),
                 notes: TEXTE
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          case arguments["geste"]
          when "ajouter"
            sujet = sujet!(arguments)
            attributs = attributs!(arguments)
            raise Error, "Donne le libellé de la tâche." if attributs[:label].blank?

            tache = sujet.map_tasks.new(created_by: user, **attributs)
            valide!(tache)
            Plan.new(resume: "Ajouter à #{nom_sujet(sujet)} : #{ligne_tache(tache).sub('Tâche # ', 'Tâche : ')}",
                     empreinte: [sujet.class.name, sujet.id, signature(arguments)],
                     donnees: { geste: "ajouter", type: sujet.class.name, id: sujet.id, attributs: attributs })
          when "modifier"
            tache = tache!(arguments["tache"])
            attributs = attributs!(arguments)
            raise Error, "Rien à modifier." if attributs.empty?

            avant = ligne_tache(tache)
            tache.assign_attributes(attributs)
            valide!(tache)
            Plan.new(resume: "Modifier (#{nom_sujet(tache.subject)})\nAvant : #{avant}\nAprès : #{ligne_tache(tache)}",
                     empreinte: [etat_de(tache), signature(arguments)], donnees: { geste: "modifier", id: tache.id, attributs: attributs })
          when "supprimer"
            tache = tache!(arguments["tache"])
            motif!({ "motif" => @motif })
            Plan.new(resume: "SUPPRIMER #{ligne_tache(tache)} (#{nom_sujet(tache.subject)}).",
                     empreinte: [etat_de(tache), "supprimer"], donnees: { geste: "supprimer", id: tache.id })
          else
            raise Error, "geste : ajouter, modifier ou supprimer."
          end
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "ajouter"
            sujet = { "Plant" => Plant, "MapFeature" => MapFeature }.fetch(d[:type]).find(d[:id])
            tache = sujet.map_tasks.create!(created_by: user, **d[:attributs])
            "#{ligne_tache(tache)} ajoutée à #{nom_sujet(sujet)}."
          when "modifier"
            tache = MapTask.with_live_subject.find(d[:id])
            tache.update!(d[:attributs])
            "#{ligne_tache(tache)} modifiée."
          else
            tache = MapTask.with_live_subject.find(d[:id])
            tache.soft_delete!(validate: false)
            "Tâche ##{tache.id} supprimée."
          end
        end

        def sujet!(arguments)
          raise Error, "Donne la plante OU l'objet de la carte." if arguments["plante"].present? == arguments["element"].present?
          return plante!(arguments["plante"]) if arguments["plante"].present?

          element = element!(arguments["element"])
          raise Error, "L'objet ##{element.id} est le point d'une plante : passe `plante`." if element.plant_point?

          element
        end

        def tache!(reference)
          MapTask.with_live_subject.includes(:subject).find_by(id: id!(reference, "tâche")) ||
            raise(Error, "Aucune tâche ##{reference.to_s.delete('#')}.")
        end

        def attributs!(arguments)
          attributs = {}
          attributs[:label] = arguments["libelle"].to_s.strip if arguments.key?("libelle")
          attributs[:sector] = arguments["filiere"] if arguments["filiere"].present?
          attributs[:frequency] = arguments["frequence"].to_s.strip.presence if arguments.key?("frequence")
          attributs[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          attributs[:months] = mois!(arguments["mois"]) if arguments.key?("mois")
          attributs
        end

        def nom_sujet(sujet)
          sujet.is_a?(Plant) ? "la plante #{nom_plante(sujet)}" : "l'objet ##{sujet.id} #{sujet.display_name.presence || 'sans nom'}"
        end
      end
    end
  end
end
