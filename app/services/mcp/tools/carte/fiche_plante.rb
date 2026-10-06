module Mcp
  module Tools
    module Carte
      # La fiche d'une plante sur la carte (PlantsController#show) : son
      # dossier, sa position, son calendrier de récolte, ses tâches et ses notes.
      class FichePlante < Base
        include Commun

        tool "fiche_plante",
             title: "Fiche d'une plante",
             description: "Le dossier complet d'une plante : espèce et variété, statut, santé, production, port, strate, " \
                          "zone, achat, plantation, dimensions adultes, position GPS, calendrier de récolte (propre ou " \
                          "hérité de l'espèce), tâches, notes datées, photos.",
             schema: { properties: { plante: PLANTE }, required: %w[plante] }

        def call(arguments)
          plante = plante!(arguments["plante"])
          lignes = [ligne_plante(plante)]
          lignes << "Espèce : #{plante.plant_species&.full_name || '—'}#{" ##{plante.plant_species_id}" if plante.plant_species_id} · " \
                    "variété : #{plante.plant_variety&.name || '—'}"
          dossier = {
            "Production" => plante.production_label, "Port" => plante.habit_label, "Population" => plante.population_label,
            "Nombre de plants" => plante.plant_count, "Conditionnement" => plante.stock_type_label, "Pépinière" => plante.nursery,
            "Prix d'achat" => (euros(plante.purchase_price_cents) if plante.purchase_price_cents),
            "Plantée le" => (I18n.l(plante.planted_on) if plante.planted_on), "Année de plantation" => (plante.planted_year unless plante.planted_on),
            "Altitude" => (plante.altitude && "#{plante.altitude} m"), "Fiche Notion" => plante.notion_url
          }.compact_blank
          lignes << dossier.map { |cle, valeur| "#{cle} : #{valeur}" }.join(" · ") if dossier.any?
          dimensions = plante.mature_dimensions
          origine = { "plant" => "saisies", "species" => "d'après l'espèce", "stratum" => "valeur type de la strate" }[dimensions[:source]]
          lignes << "Taille adulte : #{dimensions[:height]} m de haut, #{dimensions[:spread]} m d'envergure (#{origine})"
          lignes << "Notes : #{plante.notes}" if plante.notes.present?
          lignes << "Photos : #{plante.photos.size}" if plante.photos.attached?

          fenetres = plante.harvest_windows_effective
          titre = plante.harvest_windows_inherited? ? "Récolte (héritée de l'espèce)" : "Récolte"
          lignes << "#{titre} : #{fenetres.any? ? fenetres.map { |f| ligne_fenetre(f) }.join(' · ') : 'aucune fenêtre'}"

          taches = plante.map_tasks.ordered.to_a
          lignes << "Tâches :\n#{taches.map { |t| "  #{ligne_tache(t)}" }.join("\n")}" if taches.any?
          notes = plante.map_notes.includes(:author).limit(10).to_a
          lignes << "Notes datées :\n#{notes.map { |n| "  #{ligne_note(n)}" }.join("\n")}" if notes.any?
          lignes << "Objet de la carte ##{plante.map_feature_id}" if plante.placed?
          lignes.join("\n")
        end
      end
    end
  end
end
