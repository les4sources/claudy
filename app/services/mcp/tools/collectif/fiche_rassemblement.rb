module Mcp
  module Tools
    module Collectif
      # La page d'un rassemblement (GatheringsController#show) : ordre du jour
      # par liste avec les notes de réunion, actions, décisions, compte rendu.
      class FicheRassemblement < Base
        include Commun

        tool "fiche_rassemblement",
             title: "Fiche d'un rassemblement",
             description: "Le détail d'un rassemblement : ordre du jour par liste (informations, triage, décisions, " \
                          "atelier) avec auteur, porteur, état et notes prises en réunion ; actions décidées et qui les " \
                          "porte ; décisions rattachées ; notes de préparation ; compte rendu ; commentaires.",
             schema: { properties: { rassemblement: RASSEMBLEMENT }, required: %w[rassemblement] }

        def call(arguments)
          g = rassemblement!(arguments["rassemblement"])
          [ligne_rassemblement(g), texte_bloc("Notes de préparation", g.notes), odj(g), actions(g), decisions(g),
           texte_bloc("Compte rendu", g.report), commentaires(g)].compact.join("\n\n")
        end

        private

        def texte_bloc(titre, riche)
          texte = texte_riche(riche)
          texte.present? ? "#{titre} :\n#{texte}" : nil
        end

        def odj(g)
          points = g.agenda_items.includes(:author, :carrier, :notes).to_a
          return "Ordre du jour : vide." if points.empty?

          blocs = AgendaItem.lists.keys.filter_map do |liste|
            dans = points.select { |p| p.list == liste }.sort_by { |p| [p.position.to_i, p.id] }
            next if dans.empty?

            lignes = dans.map do |p|
              note = p.notes.find { |n| n.gathering_id == g.id }
              ligne = "- Point ##{p.id} #{p.completed? ? '[traité] ' : ''}#{p.title} (par #{p.author&.name}" \
                      "#{", porté par #{p.carrier.name}" if p.carrier})"
              description = texte_riche(p.description)
              ligne += "\n    #{description.gsub("\n", "\n    ")}" if description.present?
              note_texte = note && texte_riche(note.body)
              ligne += "\n    Note de réunion : #{note_texte.gsub("\n", "\n    ")}" if note_texte.present?
              ligne
            end
            "#{AgendaItem.list_label(liste)} :\n#{lignes.join("\n")}"
          end
          "Ordre du jour :\n#{blocs.join("\n")}"
        end

        def actions(g)
          liste = g.gathering_actions.includes(:assignees).to_a
          return nil if liste.empty?

          lignes = liste.map do |a|
            "- Action ##{a.id} #{a.completed? ? '[faite] ' : ''}#{a.label}#{" → #{a.assignees.map(&:name).join(', ')}" if a.assignees.any?}"
          end
          "Actions :\n#{lignes.join("\n")}"
        end

        def decisions(g)
          liste = g.decisions.recent.to_a
          return nil if liste.empty?

          "Décisions :\n#{liste.map { |d| "- #{ligne_decision(d)}" }.join("\n")}"
        end

        def commentaires(g)
          liste = g.comments.chronological.includes(:author).last(10)
          return nil if liste.empty?

          "Commentaires :\n#{liste.map { |c| "- #{I18n.l(c.created_at, format: '%d/%m %H:%M')} #{c.author&.human&.name || c.author&.email} : #{texte_riche(c.body)}" }.join("\n")}"
        end
      end
    end
  end
end
