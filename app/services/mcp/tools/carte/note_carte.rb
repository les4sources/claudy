module Mcp
  module Tools
    module Carte
      # Les notes datées d'une plante (MapNotesController) ou d'un objet de la
      # carte : « 12 mars : bourgeons gelés ».
      class NoteCarte < Ecriture
        include Commun

        tool "note_carte",
             title: "Note datée sur la carte",
             description: "`ajouter` une note datée (« bourgeons gelés ») à une `plante` ou à un `element` de la carte, " \
                          "ou `supprimer` une `note` (#id, rendu par les fiches ; motif obligatoire).",
             schema: {
               properties: {
                 geste: { type: "string", enum: %w[ajouter supprimer] },
                 plante: PLANTE,
                 element: ELEMENT,
                 note: { type: %w[integer string], description: "La note (#id), pour supprimer." },
                 texte: TEXTE,
                 date: DATE.merge(description: "Date de la note (défaut : aujourd'hui).")
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          if arguments["geste"] == "supprimer"
            note = MapNote.with_live_subject.includes(:author).find_by(id: id!(arguments["note"], "note")) ||
                   raise(Error, "Aucune note ##{arguments['note'].to_s.delete('#')}.")
            motif!({ "motif" => @motif })
            return Plan.new(resume: "SUPPRIMER #{ligne_note(note)}", empreinte: [etat_de(note)], donnees: { id: note.id })
          end
          raise Error, "geste : ajouter ou supprimer." unless arguments["geste"] == "ajouter"
          raise Error, "Donne la plante OU l'objet de la carte." if arguments["plante"].present? == arguments["element"].present?

          sujet = arguments["plante"].present? ? plante!(arguments["plante"]) : element!(arguments["element"])
          sujet = sujet.plant if sujet.is_a?(MapFeature) && sujet.plant_point? && sujet.plant
          date = date_ou_nil(arguments["date"], "date") || Date.current

          note = valide!(sujet.map_notes.new(author: user, body: arguments["texte"], noted_on: date))
          quoi = sujet.is_a?(Plant) ? "la plante #{nom_plante(sujet)}" : "l'objet ##{sujet.id} #{sujet.display_name}"
          Plan.new(resume: "Noter sur #{quoi}, le #{I18n.l(date)} : « #{note.body} »",
                   empreinte: [sujet.class.name, sujet.id, note.body, date.iso8601],
                   donnees: { type: sujet.class.name, id: sujet.id, texte: note.body, date: date.iso8601 })
        end

        def appliquer(plan)
          d = plan.donnees
          if d[:type].nil?
            note = MapNote.find(d[:id])
            note.soft_delete!(validate: false)
            return "Note ##{note.id} supprimée."
          end

          sujet = { "Plant" => Plant, "MapFeature" => MapFeature }.fetch(d[:type]).find(d[:id])
          note = sujet.map_notes.create!(author: user, body: d[:texte], noted_on: Date.iso8601(d[:date]))
          "#{ligne_note(note)} ajoutée."
        end
      end
    end
  end
end
