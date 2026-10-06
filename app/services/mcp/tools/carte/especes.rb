module Mcp
  module Tools
    module Carte
      # Carte > Espèces (PlantSpeciesController#index et #show) : le catalogue
      # local des espèces nourricières, ou la fiche d'une espèce.
      class Especes < Base
        include Commun

        tool "especes",
             title: "Catalogue des espèces",
             description: "Sans `espece` : le catalogue (#id, nom, nom latin, plantes vivantes, à placer, récolte par " \
                          "défaut), filtrable par `recherche`. Avec `espece` : sa fiche botanique, ses variétés et leurs " \
                          "plantes, son calendrier de récolte par défaut, ses plantes.",
             schema: {
               properties: {
                 espece: ESPECE,
                 recherche: { type: "string", description: "Nom ou nom latin, casse et accents ignorés." }
               }
             }

        def call(arguments)
          return fiche(espece!(arguments["espece"])) if arguments["espece"].present?

          especes = PlantSpecies.search(arguments["recherche"]).ordered.includes(:harvest_windows).to_a
          return "Aucune espèce ne correspond." if especes.empty?

          vivantes = Plant.alive.where(plant_species_id: especes.map(&:id))
          comptes = vivantes.group(:plant_species_id).count
          a_placer = vivantes.to_place.group(:plant_species_id).count
          lignes = especes.map do |espece|
            recolte = espece.harvest_windows.map { |f| ligne_fenetre(f) }.join(" · ")
            "Espèce ##{espece.id} #{espece.full_name} · #{comptes.fetch(espece.id, 0)} plante(s) vivante(s)" \
              "#{", #{a_placer[espece.id]} à placer" if a_placer[espece.id]}#{" · #{recolte}" if recolte.present?}"
          end
          "#{especes.size} espèce(s) :\n#{lignes.join("\n")}"
        end

        private

        def fiche(espece)
          lignes = ["Espèce ##{espece.id} #{espece.full_name}"]
          botanique = {
            "Famille" => espece.family, "Noms communs" => espece.common_names, "Rusticité" => espece.hardiness,
            "Hauteur" => espece.height, "Envergure" => espece.spread, "Exposition" => espece.exposure.join(", "),
            "Parties comestibles" => espece.edible_parts.join(", "), "Wikipédia" => espece.wikipedia_url
          }.compact_blank
          lignes << botanique.map { |cle, valeur| "#{cle} : #{valeur}" }.join(" · ") if botanique.any?
          lignes << "Notes : #{espece.notes}" if espece.notes.present?
          lignes << "Récolte par défaut : #{espece.harvest_windows.map { |f| ligne_fenetre(f) }.join(' · ').presence || 'aucune fenêtre'}"

          par_variete = espece.plants.alive.group(:plant_variety_id).count
          varietes = espece.varieties.map { |v| "#{v.name} ##{v.id} (#{par_variete.fetch(v.id, 0)})" }
          lignes << "Variétés : #{varietes.join(', ').presence || 'aucune'}"
          plantes = espece.plants.includes(:plant_variety, :map_feature).ordered.to_a
          lignes << "Plantes (#{plantes.size}) :\n#{plantes.map { |p| "  #{ligne_plante(p)}" }.join("\n")}" if plantes.any?
          lignes.join("\n")
        end
      end
    end
  end
end
