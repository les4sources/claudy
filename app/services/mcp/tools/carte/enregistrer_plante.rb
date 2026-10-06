module Mcp
  module Tools
    module Carte
      # La fiche d'une plante (PlantsController#create, #update, #place,
      # #unplace, #destroy) : son dossier, sa position sur la carte, sa
      # suppression. L'espèce et la variété arrivent par leur NOM et sont
      # créées au besoin, comme dans la fiche.
      class EnregistrerPlante < Ecriture
        include Commun

        CHAMPS_LIBRES = {
          "nom" => :name, "zone" => :zone, "pepiniere" => :nursery, "notion" => :notion_url, "notes" => :notes
        }.freeze
        LISTES = {
          "statut" => [:status, Plant::STATUSES], "sante" => [:health, Plant::HEALTHS],
          "production" => [:production, Plant::PRODUCTIONS], "port" => [:habit, Plant::HABITS],
          "strate" => [:stratum, Plant::STRATA], "population" => [:population, Plant::POPULATIONS],
          "conditionnement" => [:stock_type, Plant::STOCK_TYPES]
        }.freeze
        NOMBRES = {
          "nombre" => :plant_count, "annee" => :planted_year, "altitude" => :altitude,
          "hauteur_adulte" => :mature_height, "envergure_adulte" => :mature_spread
        }.freeze
        LIBELLES = {
          name: "nom", number: "numéro", zone: "zone", status: "statut", health: "santé", production: "production",
          habit: "port", stratum: "strate", population: "population", stock_type: "conditionnement",
          plant_count: "nombre de plants", nursery: "pépinière", purchase_price_cents: "prix d'achat (cents)",
          planted_on: "plantée le", planted_year: "année", altitude: "altitude", mature_height: "hauteur adulte",
          mature_spread: "envergure adulte", notion_url: "fiche Notion", notes: "notes",
          plant_species_id: "espèce", plant_variety_id: "variété", map_feature_id: "point sur la carte"
        }.freeze

        tool "enregistrer_plante",
             title: "Enregistrer une plante",
             description: "Crée une plante (sans `plante`) ou modifie son dossier : espèce et variété par leur NOM " \
                          "(créées dans le catalogue si elles n'existent pas), zone, statut, santé, strate… Une chaîne " \
                          "vide efface un champ. `latitude` + `longitude` la placent (ou la déplacent) sur la carte ; " \
                          "`retirer_de_la_carte: true` retire son point (elle redevient « à placer ») ; " \
                          "`supprimer: true` la supprime avec son point (motif obligatoire). Les listes fermées " \
                          "acceptent la clé ou le libellé français.",
             schema: {
               properties: {
                 plante: PLANTE,
                 nom: { type: "string", description: "Nom propre (défaut : espèce + variété)." },
                 numero: { type: "string", description: "Numéro de terrain (42, 9.1)." },
                 espece: { type: "string", description: "Nom de l'espèce (« Pommier »). Vide : retire l'espèce et la variété." },
                 variete: { type: "string", description: "Nom de la variété, au sein de l'espèce." },
                 nom_latin: { type: "string", description: "Seulement pour une espèce nouvelle." },
                 famille: { type: "string", description: "Seulement pour une espèce nouvelle." },
                 zone: { type: "string" },
                 statut: { type: "string", description: Plant::STATUSES.keys.join(", ") },
                 sante: { type: "string", description: Plant::HEALTHS.keys.join(", ") },
                 production: { type: "string", description: Plant::PRODUCTIONS.keys.join(", ") },
                 port: { type: "string", description: Plant::HABITS.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 strate: { type: "string", description: Plant::STRATA.keys.join(", ") },
                 population: { type: "string", description: Plant::POPULATIONS.keys.join(", ") },
                 conditionnement: { type: "string", description: Plant::STOCK_TYPES.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 nombre: { type: %w[integer string], description: "Nombre de plants." },
                 pepiniere: { type: "string" },
                 prix: { type: "string", description: "Prix d'achat en euros (24,50)." },
                 plantee_le: DATE,
                 annee: { type: %w[integer string], description: "Année de plantation, si la date n'est pas connue." },
                 altitude: { type: %w[number string] },
                 hauteur_adulte: { type: %w[number string], description: "Mètres." },
                 envergure_adulte: { type: %w[number string], description: "Mètres." },
                 notion: { type: "string", description: "Lien vers la fiche Notion." },
                 notes: { type: "string" },
                 latitude: LATITUDE,
                 longitude: LONGITUDE,
                 retirer_de_la_carte: { type: "boolean" },
                 supprimer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          plante = arguments["plante"].present? ? plante!(arguments["plante"]) : nil
          return plan_suppression(plante) if arguments["supprimer"]

          donnees = { id: plante&.id, attributs: attributs!(arguments), especes: especes(arguments) }
          if arguments.key?("latitude") || arguments.key?("longitude")
            donnees[:position] = coordonnees!(arguments["latitude"], arguments["longitude"])
          end
          raise Error, "latitude et retirer_de_la_carte s'excluent." if donnees[:position] && arguments["retirer_de_la_carte"]

          donnees[:retirer] = true if arguments["retirer_de_la_carte"]
          raise Error, "Rien à enregistrer." if plante && donnees.except(:id).values.all?(&:blank?)

          apres = simuler { ecrire(donnees) }
          titre = plante ? "Modifier #{nom_plante(plante)}" : "Nouvelle plante"
          Plan.new(resume: "#{titre}\n#{apres}", empreinte: [plante && etat_de(plante), signature(arguments)], donnees: donnees)
        end

        def appliquer(plan)
          return supprimer(plan.donnees[:id]) if plan.donnees[:supprimer]

          "Plante enregistrée.\n#{ecrire(plan.donnees)}"
        end

        def attributs!(arguments)
          attributs = {}
          CHAMPS_LIBRES.each { |cle, colonne| attributs[colonne] = arguments[cle].to_s if arguments.key?(cle) }
          LISTES.each { |cle, (colonne, choix)| attributs[colonne] = choix!(arguments[cle], choix, cle) if arguments.key?(cle) }
          NOMBRES.each { |cle, colonne| attributs[colonne] = nombre!(arguments[cle], cle) if arguments.key?(cle) }
          attributs[:number] = arguments["numero"].to_s.strip.delete_prefix("#").tr(",", ".").presence if arguments.key?("numero")
          attributs[:purchase_price_cents] = prix!(arguments["prix"]) if arguments.key?("prix")
          if arguments.key?("plantee_le")
            attributs[:planted_on] = date_ou_nil(arguments["plantee_le"], "plantee_le")&.iso8601
            attributs[:planted_year] = Date.iso8601(attributs[:planted_on]).year if attributs[:planted_on]
          end
          raise Error, "Le statut est obligatoire : il ne s'efface pas." if attributs.key?(:status) && attributs[:status].nil?

          attributs
        end

        def especes(arguments)
          return nil unless arguments.key?("espece") || arguments.key?("variete")

          { espece: (arguments["espece"].to_s.squish if arguments.key?("espece")), variete: arguments["variete"].to_s.squish,
            botanique: { latin_name: arguments["nom_latin"].to_s.squish, family: arguments["famille"].to_s.squish }.compact_blank }
        end

        def nombre!(valeur, champ)
          return nil if valeur.to_s.strip.empty?

          texte = valeur.to_s.strip.tr(",", ".")
          raise Error, "#{champ} : nombre illisible « #{valeur} »." unless texte.match?(/\A\d+(\.\d+)?\z/)

          texte
        end

        def prix!(valeur)
          texte = valeur.to_s.delete("€").delete(" ").tr(",", ".")
          return nil if texte.empty?

          montant = BigDecimal(texte, exception: false)
          raise Error, "Prix d'achat illisible : « #{valeur} » (en euros, par exemple 24,50)." if montant.nil? || montant.negative?

          (montant * 100).round.to_i
        end

        def ecrire(d)
          plante = d[:id] ? Plant.find(d[:id]) : Plant.new(created_by: user, status: "planted", planted_on: Date.current)
          avant = plante.attributes.slice(*LIBELLES.keys.map(&:to_s))
          plante.assign_attributes(d[:attributs])
          plante.planted_year = plante.planted_on.year if plante.planted_on
          rattacher_espece(plante, d[:especes]) if d[:especes]
          valide!(plante)
          plante.save!
          plante.place!(latitude: d[:position][0], longitude: d[:position][1], user: user) if d[:position]
          plante.unplace! if d[:retirer] && plante.placed?
          plante.reload
          changements = plante.attributes.slice(*avant.keys).reject { |cle, valeur| avant[cle] == valeur }
          lignes = [ligne_plante(plante)]
          lignes << "Espèce : #{plante.plant_species&.full_name || '—'} · variété : #{plante.plant_variety&.name || '—'}"
          if d[:id] && changements.any?
            lignes << "Changements : #{changements.map { |cle, valeur| "#{LIBELLES[cle.to_sym]} #{avant[cle].inspect} → #{valeur.inspect}" }.join(' · ')}"
          end
          lignes.join("\n")
        end

        # Comme `PlantsController#assign_species` : l'espèce par son nom,
        # créée si besoin ; le nom latin et la famille ne servent qu'à une
        # espèce nouvelle. Vider l'espèce retire aussi la variété.
        def rattacher_espece(plante, d)
          nom = d[:espece].nil? ? plante.plant_species&.name.to_s : d[:espece]
          espece = nom.present? ? PlantSpecies.find_or_create_by_name!(nom, created_by: user, **d[:botanique]) : nil
          plante.plant_species = espece
          if d[:variete].blank?
            plante.plant_variety = nil
          elsif espece
            plante.plant_variety = espece.find_or_create_variety!(d[:variete])
          else
            raise Error, "Une variété appartient à une espèce : indique d'abord l'espèce de « #{d[:variete]} »."
          end
        end

        def plan_suppression(plante)
          raise Error, "Donne la plante à supprimer." if plante.nil?

          motif!({ "motif" => @motif })
          Plan.new(resume: "SUPPRIMER #{ligne_plante(plante)}#{' et son point sur la carte' if plante.placed?}. " \
                           "Ses notes, tâches et fenêtres de récolte restent dans l'historique.",
                   empreinte: [etat_de(plante), "supprimer"], donnees: { id: plante.id, supprimer: true })
        end

        def supprimer(id)
          plante = Plant.find(id)
          plante.soft_delete!(validate: false)
          "#{nom_plante(plante)} supprimée."
        end
      end
    end
  end
end
