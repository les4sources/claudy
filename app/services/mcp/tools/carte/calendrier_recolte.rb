module Mcp
  module Tools
    module Carte
      # Le calendrier de récolte d'une plante (PlantHarvestsController) ou
      # celui, par défaut, d'une espèce (SpeciesHarvestsController). Une plante
      # sans fenêtre propre suit son espèce ; en avoir une seule, c'est
      # remplacer tout le calendrier de l'espèce pour cette plante.
      class CalendrierRecolte < Ecriture
        include Commun

        tool "calendrier_recolte",
             title: "Calendrier de récolte",
             description: "Fixe quand récolter quoi, pour une `plante` ou une `espece` (défaut de ses plantes). " \
                          "`recoltes` REMPLACE tout le calendrier du porteur : {\"fruit\": [9, 10], \"fleur\": " \
                          "[\"mai\"]}. Pour une plante qui suit son espèce, donner `recoltes` lui fait un calendrier " \
                          "propre (pense à y remettre les parties de l'espèce à garder). `effacer: true` supprime le " \
                          "calendrier : la plante revient à celui de son espèce ; l'espèce n'en a plus.",
             schema: {
               properties: {
                 plante: PLANTE,
                 espece: ESPECE,
                 recoltes: {
                   type: "object", additionalProperties: MOIS,
                   description: "Partie → mois. Parties : #{PlantHarvestWindow::PARTS.map { |k, v| "#{k} (#{v})" }.join(', ')}."
                 },
                 effacer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          raise Error, "Donne la plante OU l'espèce." if arguments["plante"].present? == arguments["espece"].present?

          porteur = arguments["plante"].present? ? plante!(arguments["plante"]) : espece!(arguments["espece"])
          raise Error, "Donne `recoltes` ou `effacer: true`." if arguments["recoltes"].nil? && !arguments["effacer"]
          raise Error, "`recoltes` et `effacer` s'excluent." if arguments["recoltes"] && arguments["effacer"]

          parties = arguments["effacer"] ? [] : parties!(arguments["recoltes"])
          raise Error, "`recoltes` est vide : pour tout retirer, passe `effacer: true`." if !arguments["effacer"] && parties.empty?

          donnees = { type: porteur.class.name, id: porteur.id, parties: parties }
          apres = simuler { ecrire(donnees) }
          Plan.new(resume: "#{titre(porteur)}\nAvant : #{calendrier(porteur)}\nAprès : #{apres}",
                   empreinte: [etat_de(porteur), porteur.harvest_windows.map { |f| [f.part, f.months] }, parties],
                   donnees: donnees)
        end

        def appliquer(plan)
          "Calendrier enregistré : #{ecrire(plan.donnees)}"
        end

        def ecrire(d)
          porteur = { "Plant" => Plant, "PlantSpecies" => PlantSpecies }.fetch(d[:type]).find(d[:id])
          if d[:parties].empty?
            porteur.harvest_windows.destroy_all
          else
            _brouillon, erreurs = PlantHarvestWindow.replace_for(porteur, d[:parties])
            raise Error, erreurs.to_sentence if erreurs.any?
          end
          calendrier(porteur.reload)
        end

        def parties!(valeur)
          raise Error, "recoltes : un objet {partie: [mois]}." unless valeur.is_a?(Hash)

          voulues = valeur.to_h { |partie, mois| [choix!(partie, PlantHarvestWindow::PARTS, "partie"), mois!(mois, partie)] }
          vides = voulues.select { |_, mois| mois.empty? }.keys
          raise Error, "#{vides.map { |p| PlantHarvestWindow.part_label(p) }.join(', ')} : donne au moins un mois, ou retire la partie." if vides.any?

          PlantHarvestWindow::PARTS.keys.filter_map { |partie| [partie, voulues[partie]] if voulues.key?(partie) }
        end

        def titre(porteur)
          porteur.is_a?(Plant) ? "Récolte de #{nom_plante(porteur)}" : "Récolte par défaut de l'espèce #{porteur.name}"
        end

        def calendrier(porteur)
          if porteur.is_a?(Plant)
            fenetres = porteur.harvest_windows_effective
            texte = fenetres.map { |f| ligne_fenetre(f) }.join(" · ").presence || "aucune fenêtre"
            porteur.harvest_windows_inherited? ? "#{texte} (hérité de l'espèce)" : texte
          else
            porteur.harvest_windows.map { |f| ligne_fenetre(f) }.join(" · ").presence || "aucune fenêtre"
          end
        end
      end
    end
  end
end
