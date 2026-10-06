module Mcp
  module Tools
    module Carte
      # Carte > Plantes (PlantsController#index) : toutes les plantes du
      # domaine, recherche et filtres, triées par numéro.
      class Plantes < Base
        include Commun

        PAR_PAGE = 60

        tool "plantes",
             title: "Plantes du domaine",
             description: "Liste les plantes nourricières (#id, n° de terrain, espèce et variété, statut, santé, strate, " \
                          "zone, placée ou à placer). Recherche par nom, numéro, espèce, nom latin ou variété ; filtres. " \
                          "Pour le dossier complet d'une plante : fiche_plante.",
             schema: {
               properties: {
                 recherche: { type: "string", description: "Nom, numéro (42, #42), espèce, nom latin, variété. Casse et accents ignorés." },
                 statut: { type: "string", description: "#{Plant::STATUSES.map { |k, v| "#{k} (#{v})" }.join(', ')}." },
                 sante: { type: "string", description: Plant::HEALTHS.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 strate: { type: "string", description: Plant::STRATA.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 zone: { type: "string", description: "Zone exacte (« Verger »)." },
                 placee: { type: "string", enum: %w[oui non], description: "oui : sur la carte ; non : vivantes à placer." },
                 page: { type: "integer", description: "Page (#{PAR_PAGE} plantes par page)." }
               }
             }

        def call(arguments)
          scope = Plant.search(arguments["recherche"]).in_zone(arguments["zone"].to_s.squish.presence)
          statut = choix!(arguments["statut"], Plant::STATUSES, "statut")
          scope = scope.with_status(statut) if statut
          sante = choix!(arguments["sante"], Plant::HEALTHS, "santé")
          scope = scope.where(health: sante) if sante
          strate = choix!(arguments["strate"], Plant::STRATA, "strate")
          scope = scope.where(stratum: strate) if strate
          scope = scope.placed if arguments["placee"] == "oui"
          scope = scope.alive.to_place if arguments["placee"] == "non"

          total = scope.count
          page = [arguments["page"].to_i, 1].max
          plantes = scope.ordered.includes(:plant_species, :plant_variety, :map_feature)
                         .offset((page - 1) * PAR_PAGE).limit(PAR_PAGE).to_a

          entete = "Domaine : #{Plant.count} plantes, #{Plant.alive.placed.count} placées, " \
                   "#{Plant.alive.to_place.count} vivantes à placer, #{Plant.where(status: Plant::DEAD).count} mortes. " \
                   "Zones : #{Plant.zones.join(', ').presence || 'aucune'}."
          return "#{entete}\nAucune plante ne correspond." if plantes.empty?

          suite = total > page * PAR_PAGE ? "\n… #{total - page * PAR_PAGE} de plus : page #{page + 1}." : ""
          "#{entete}\n#{total} plante(s) trouvée(s)#{" (page #{page})" if page > 1} :\n" \
            "#{plantes.map { |p| ligne_plante(p) }.join("\n")}#{suite}"
        end
      end
    end
  end
end
