module Mcp
  module Tools
    module Carte
      # Carte > Récoltes (HarvestCalendarController#index) : ce qui se récolte
      # au domaine, mois par mois. Une plante sans fenêtre propre suit celles
      # de son espèce ; les plantes mortes ne se récoltent plus.
      class CalendrierRecoltes < Base
        include Commun

        tool "calendrier_recoltes",
             title: "Calendrier des récoltes",
             description: "Ce qui se récolte, mois par mois : espèce (ou plante) et partie, avec les plantes concernées. " \
                          "Défaut : les douze mois. Filtres : mois, partie, zone.",
             schema: {
               properties: {
                 mois: MOIS.merge(description: "Les mois à montrer (numéros ou noms). Défaut : les douze."),
                 partie: { type: "string", description: PlantHarvestWindow::PARTS.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 zone: { type: "string", description: "Zone exacte (« Verger »)." }
               }
             }

        def call(arguments)
          partie = choix!(arguments["partie"], PlantHarvestWindow::PARTS, "partie")
          zone = arguments["zone"].to_s.squish.presence
          mois = arguments["mois"].present? ? mois!(arguments["mois"]) : MapTask::MONTHS
          calendrier = Plant.in_zone(zone).harvest_calendar(part: partie)

          sections = mois.map do |m|
            groupes = calendrier.fetch(m).group_by { |plante, fenetre| [plante.plant_species_id || "p#{plante.id}", fenetre.part] }
            lignes = groupes.map do |_, paires|
              plantes = paires.map(&:first).uniq
              titre = plantes.one? ? nom_plante(plantes.first) : "#{plantes.first.plant_species&.name} ×#{plantes.size}"
              noms = plantes.many? ? " (#{plantes.first(12).map { |p| nom_plante(p) }.join(', ')}#{'…' if plantes.size > 12})" : ""
              "  #{titre} — #{paires.first.last.part_label}#{noms}"
            end.sort
            "#{MapTask.month_name(m)} : #{lignes.empty? ? 'rien' : "\n#{lignes.join("\n")}"}"
          end
          filtres = [("partie #{PlantHarvestWindow.part_label(partie)}" if partie), ("zone #{zone}" if zone)].compact
          "Calendrier des récoltes#{" (#{filtres.join(', ')})" if filtres.any?}\n#{sections.join("\n")}"
        end
      end
    end
  end
end
