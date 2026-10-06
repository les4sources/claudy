module Mcp
  module Tools
    module Carte
      # La fiche d'une espèce (PlantSpeciesController#update, #destroy) et ses
      # variétés (PlantVarietiesController). Une espèce ou une variété ne se
      # supprime pas tant qu'une plante vivante la porte.
      class EnregistrerEspece < Ecriture
        include Commun

        CHAMPS = {
          "nom" => :name, "nom_latin" => :latin_name, "famille" => :family, "noms_communs" => :common_names,
          "rusticite" => :hardiness, "hauteur" => :height, "envergure" => :spread, "wikipedia" => :wikipedia_url, "notes" => :notes
        }.freeze

        tool "enregistrer_espece",
             title: "Enregistrer une espèce du catalogue",
             description: "Crée une espèce (sans `espece`, avec `nom`) ou modifie sa fiche botanique : nom, nom latin, " \
                          "famille, noms communs, rusticité, hauteur, envergure (texte libre, « 5-7 m »), exposition, " \
                          "parties comestibles, Wikipédia, notes. Gère aussi ses variétés : `varietes_ajouter`, " \
                          "`varietes_renommer` ({ancien: nouveau}), `varietes_supprimer` (refusé si une plante vivante la " \
                          "porte). `supprimer: true` retire l'espèce du catalogue (refusé tant que des plantes vivantes " \
                          "en dépendent ; motif obligatoire).",
             schema: {
               properties: {
                 espece: ESPECE,
                 nom: { type: "string" }, nom_latin: { type: "string" }, famille: { type: "string" },
                 noms_communs: { type: "string" }, rusticite: { type: "string" },
                 hauteur: { type: "string" }, envergure: { type: "string" },
                 exposition: { type: "array", items: { type: "string" }, description: "Soleil, Mi-ombre, Ombre. Remplace la liste." },
                 parties_comestibles: { type: "array", items: { type: "string" }, description: "Remplace la liste." },
                 wikipedia: { type: "string" }, notes: { type: "string" },
                 varietes_ajouter: { type: "array", items: { type: "string" } },
                 varietes_renommer: { type: "object", additionalProperties: { type: "string" } },
                 varietes_supprimer: { type: "array", items: { type: "string" } },
                 supprimer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          espece = arguments["espece"].present? ? espece!(arguments["espece"]) : nil
          return plan_suppression(espece) if arguments["supprimer"]
          raise Error, "Donne le nom de la nouvelle espèce." if espece.nil? && arguments["nom"].blank?
          if espece.nil? && (doublon = PlantSpecies.named(arguments["nom"]).first)
            raise Error, "« #{doublon.name} » existe déjà (##{doublon.id}) : passe `espece` pour la modifier."
          end

          attributs = CHAMPS.each_with_object({}) { |(cle, colonne), h| h[colonne] = arguments[cle].to_s.strip.presence if arguments.key?(cle) }
          attributs[:exposure] = Array(arguments["exposition"]) if arguments.key?("exposition")
          attributs[:edible_parts] = Array(arguments["parties_comestibles"]) if arguments.key?("parties_comestibles")
          varietes = {
            ajouter: Array(arguments["varietes_ajouter"]).map { |n| n.to_s.squish }.compact_blank,
            renommer: arguments["varietes_renommer"].to_h.transform_values { |n| n.to_s.squish },
            supprimer: Array(arguments["varietes_supprimer"]).map { |n| n.to_s.squish }.compact_blank
          }
          raise Error, "Rien à enregistrer." if espece && attributs.empty? && varietes.values.all?(&:empty?)

          donnees = { id: espece&.id, attributs: attributs, varietes: varietes }
          apres = simuler { ecrire(donnees) }
          Plan.new(resume: "#{espece ? "Modifier l'espèce ##{espece.id} #{espece.name}" : 'Nouvelle espèce'}\n#{apres}",
                   empreinte: [espece && etat_de(espece), espece&.varieties&.map { |v| etat_de(v) }, signature(arguments)],
                   donnees: donnees)
        end

        def appliquer(plan)
          return supprimer(plan.donnees[:id]) if plan.donnees[:supprimer]

          "Espèce enregistrée.\n#{ecrire(plan.donnees)}"
        end

        def ecrire(d)
          espece = d[:id] ? PlantSpecies.find(d[:id]) : PlantSpecies.new(created_by: user)
          espece.assign_attributes(d[:attributs])
          valide!(espece)
          espece.save!
          notes = []
          d[:varietes][:renommer].each do |ancien, nouveau|
            variete = variete!(espece, ancien)
            variete.name = nouveau
            valide!(variete).save!
            notes << "« #{ancien} » devient « #{variete.name} »"
          end
          d[:varietes][:ajouter].each do |nom|
            variete = valide!(espece.varieties.new(name: nom))
            variete.save!
            notes << "variété « #{variete.name} » ajoutée"
          end
          d[:varietes][:supprimer].each do |nom|
            variete = variete!(espece, nom)
            vivantes = variete.plants.alive.count
            raise Error, "« #{variete.name} » est portée par #{vivantes} plante(s) vivante(s) : change-leur de variété d'abord." if vivantes.positive?

            variete.soft_delete!(validate: false)
            notes << "variété « #{variete.name} » supprimée"
          end
          espece.reload
          ["Espèce ##{espece.id} #{espece.full_name}",
           ({ "Famille" => espece.family, "Noms communs" => espece.common_names, "Rusticité" => espece.hardiness,
              "Hauteur" => espece.height, "Envergure" => espece.spread, "Exposition" => espece.exposure.join(", "),
              "Parties comestibles" => espece.edible_parts.join(", ") }.compact_blank.map { |k, v| "#{k} : #{v}" }.join(" · ").presence),
           "Variétés : #{espece.varieties.map(&:name).join(', ').presence || 'aucune'}",
           (notes.join(" · ").upcase_first if notes.any?)].compact.join("\n")
        end

        def variete!(espece, nom)
          espece.varieties.named(nom).first ||
            raise(Error, "#{espece.name} n'a pas de variété « #{nom} ». Variétés : #{espece.varieties.map(&:name).join(', ').presence || 'aucune'}.")
        end

        def plan_suppression(espece)
          raise Error, "Donne l'espèce à retirer du catalogue." if espece.nil?

          vivantes = espece.plants.alive.count
          if vivantes.positive?
            raise Error, "Impossible de supprimer « #{espece.name} » : #{vivantes} plante(s) vivante(s) en dépendent. " \
                         "Rattache-les d'abord à une autre espèce."
          end

          motif!({ "motif" => @motif })
          Plan.new(resume: "RETIRER « #{espece.full_name} » du catalogue.", empreinte: [etat_de(espece), "supprimer"],
                   donnees: { id: espece.id, supprimer: true })
        end

        def supprimer(id)
          espece = PlantSpecies.find(id)
          espece.soft_delete!(validate: false)
          "« #{espece.name} » a été retirée du catalogue."
        end
      end
    end
  end
end
