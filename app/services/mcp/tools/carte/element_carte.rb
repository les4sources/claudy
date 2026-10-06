module Mcp
  module Tools
    module Carte
      # Un objet de la carte (MapFeaturesController#create, #update, #destroy ;
      # MapBioindicatorsController#request_analysis). Seuls les POINTS se
      # posent ou se déplacent d'ici : une zone ou un tracé se dessine sur la
      # carte, mais leur fiche (nom, consignes…) se modifie ici.
      class ElementCarte < Ecriture
        include Commun

        CHAMPS_TRADUITS = {
          "nom" => [:name_i18n, "fr"], "nom_en" => [:name_i18n, "en"], "nom_nl" => [:name_i18n, "nl"],
          "description" => [:description_i18n, "fr"], "description_en" => [:description_i18n, "en"],
          "description_nl" => [:description_i18n, "nl"]
        }.freeze
        PROPRIETES = {
          "acces" => ["access", MapFeature::ACCESS_LEVELS], "icone" => ["icon", MapFeature::WELCOME_ICONS],
          "calibre" => ["gauge", MapFeature::GAUGES], "equipement" => ["equipment", MapFeature::EQUIPMENTS],
          "origine_eau" => ["water_source", MapFeature::WATER_SOURCES]
        }.freeze
        COUCHES_POINT = %w[management welcome network].freeze
        AILLEURS = {
          "plant" => "c'est le point d'une plante : enregistrer_plante",
          "comment" => "c'est un fil de commentaires : fil_carte",
          "observation" => "c'est un relevé de biodiversité : releve_biodiversite"
        }.freeze

        tool "element_carte",
             title: "Objet de la carte",
             description: "`creer_point` : pose un point (latitude, longitude) dans la couche gestion, accueil ou un réseau " \
                          "(eau, électricité, ethernet, gaz : c'est alors un nœud, avec `type_noeud`). `modifier` la fiche " \
                          "d'un objet : nom et description (fr, en, nl), nature d'une zone d'accueil, icône, consigne de " \
                          "gestion, type de nœud, consigne, calibre, équipement, origine de l'eau d'un robinet ; une " \
                          "chaîne vide efface. Un POINT se déplace avec latitude/longitude ; une zone ou un tracé se " \
                          "redessine dans Claudy. `supprimer` (motif obligatoire). `redemander_analyse` d'un relevé de " \
                          "bio-indicatrices.",
             schema: {
               properties: {
                 geste: { type: "string", enum: %w[creer_point modifier supprimer redemander_analyse] },
                 element: ELEMENT,
                 couche: { type: "string", description: "Pour creer_point : management (gestion), welcome (accueil), ou un réseau : water, electric, ethernet, gas." },
                 latitude: LATITUDE,
                 longitude: LONGITUDE,
                 nom: { type: "string" }, nom_en: { type: "string" }, nom_nl: { type: "string" },
                 description: TEXTE, description_en: TEXTE, description_nl: TEXTE,
                 acces: { type: "string", description: MapFeature::ACCESS_LEVELS.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 icone: { type: "string", description: MapFeature::WELCOME_ICONS.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 consigne_gestion: TEXTE,
                 type_noeud: { type: "string", description: "Selon le réseau : #{MapLayer::NODE_TYPES.map { |r, t| "#{r} → #{t.keys.join('/')}" }.join(' ; ')}." },
                 consigne: { type: "string", description: "Consigne d'un nœud (« quart de tour vers la droite »)." },
                 calibre: { type: "string", description: MapFeature::GAUGES.keys.join(", ") },
                 equipement: { type: "string", description: MapFeature::EQUIPMENTS.keys.join(", ") },
                 origine_eau: { type: "string", description: MapFeature::WATER_SOURCES.map { |k, v| "#{k} (#{v})" }.join(", ") }
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          case arguments["geste"]
          when "creer_point"
            couche = couche_point!(arguments["couche"])
            lat, lng = coordonnees!(arguments["latitude"], arguments["longitude"])
            donnees = { geste: "creer_point", couche: couche.id, position: [lat, lng], champs: champs!(arguments) }
            Plan.new(resume: "Nouveau point dans #{couche.name} :\n#{simuler { ecrire(donnees) }}",
                     empreinte: [signature(arguments)], donnees: donnees)
          when "modifier"
            objet = element!(arguments["element"])
            refuser_ailleurs!(objet)
            raise Error, "Un relevé de bio-indicatrices se modifie dans Claudy." if objet.bioindicator_point?

            donnees = { geste: "modifier", id: objet.id, champs: champs!(arguments) }
            if arguments.key?("latitude") || arguments.key?("longitude")
              raise Error, "Seul un point se déplace d'ici : une zone ou un tracé se redessine sur la carte." unless objet.geometry_type == "Point"

              donnees[:position] = coordonnees!(arguments["latitude"], arguments["longitude"])
            end
            raise Error, "Rien à modifier." if donnees[:champs].empty? && donnees[:position].nil?

            Plan.new(resume: "Modifier\nAvant : #{ligne_element(objet)}\nAprès : #{simuler { ecrire(donnees) }}",
                     empreinte: [etat_de(objet), signature(arguments)], donnees: donnees)
          when "supprimer"
            objet = element!(arguments["element"])
            refuser_ailleurs!(objet, sauf: "observation")
            motif!({ "motif" => @motif })
            lieux = objet.venue_names.presence
            Plan.new(resume: "SUPPRIMER #{ligne_element(objet)}#{" (#{lieux} redeviennent « à tracer »)" if lieux}.",
                     empreinte: [etat_de(objet)], donnees: { geste: "supprimer", id: objet.id })
          when "redemander_analyse"
            objet = element!(arguments["element"])
            raise Error, "L'objet ##{objet.id} n'est pas un relevé de bio-indicatrices." unless objet.bioindicator_point?
            raise Error, "Ce relevé attend déjà son analyse." if objet.to_analyze?

            Plan.new(resume: "Redemander l'analyse du relevé ##{objet.id} (#{objet.bioindicator_title}) ; l'analyse actuelle reste lisible jusqu'à la suivante.",
                     empreinte: [etat_de(objet)], donnees: { geste: "redemander_analyse", id: objet.id })
          else
            raise Error, "geste : creer_point, modifier, supprimer ou redemander_analyse."
          end
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "supprimer"
            objet = MapFeature.find(d[:id])
            objet.soft_delete!(validate: false)
            "Objet ##{objet.id} supprimé."
          when "redemander_analyse"
            objet = MapFeature.find(d[:id])
            objet.request_bioindicator_analysis!
            "Analyse redemandée pour le relevé ##{objet.id}."
          else
            "Enregistré : #{ecrire(d)}"
          end
        end

        def ecrire(d)
          objet = if d[:geste] == "creer_point"
                    couche = MapLayer.find(d[:couche])
                    couche.map_features.new(created_by: user, feature_kind: couche.network? ? "node" : "point")
                  else
                    MapFeature.find(d[:id])
                  end
          objet.geometry = { "type" => "Point", "coordinates" => [d[:position][1], d[:position][0]] } if d[:position]
          d[:champs].each do |cle, valeur|
            if (traduit = CHAMPS_TRADUITS[cle])
              colonne, langue = traduit
              objet.public_send("#{colonne}=", objet.public_send(colonne).to_h.merge(langue => valeur.to_s.strip))
            elsif cle == "consigne_gestion"
              objet.properties = objet.properties.to_h.merge("management_notes" => valeur.to_s.strip)
            else
              objet.properties = objet.properties.to_h.merge(cle => valeur.presence).compact
            end
          end
          # Comme la fiche : un nœud qui cesse d'être un robinet perd l'origine de son eau.
          objet.properties = objet.properties.to_h.except("water_source") if objet.node? && !objet.tap?
          valide!(objet)
          objet.save!
          details = objet.properties.to_h.slice("access", "icon", "node_type", "instructions", "gauge", "equipment",
                                                 "water_source", "management_notes").compact_blank
          "#{ligne_element(objet)}#{" · #{objet.description(:fr).squish.truncate(150)}" if objet.description(:fr).present?}" \
            "#{" · #{details.map { |k, v| "#{k} #{v}" }.join(' · ')}" if details.any?}"
        end

        # Les champs donnés, en clés de la fiche. Les listes fermées acceptent la
        # clé ou le libellé ; le type de nœud dépend du réseau de la couche.
        def champs!(arguments)
          champs = {}
          CHAMPS_TRADUITS.each_key { |cle| champs[cle] = arguments[cle].to_s if arguments.key?(cle) }
          PROPRIETES.each { |cle, (propriete, choix)| champs[propriete] = choix!(arguments[cle], choix, cle).to_s if arguments.key?(cle) }
          champs["consigne_gestion"] = arguments["consigne_gestion"].to_s if arguments.key?("consigne_gestion")
          champs["instructions"] = arguments["consigne"].to_s.strip if arguments.key?("consigne")
          champs["node_type"] = arguments["type_noeud"].to_s.strip if arguments.key?("type_noeud")
          champs
        end

        def couche_point!(reference)
          texte = I18n.transliterate(reference.to_s.strip).downcase
          reseau = MapLayer::NETWORKS.find { |cle, spec| cle == texte || I18n.transliterate(spec[:name]).downcase == texte }&.first
          if reseau
            return MapLayer.ensure_networks!.find { |c| c.network == reseau }
          end

          kind = { "gestion" => "management", "accueil" => "welcome" }.fetch(texte, texte)
          raise Error, "couche : management (gestion), welcome (accueil) ou un réseau (water, electric, ethernet, gas)." unless COUCHES_POINT.include?(kind) && kind != "network"

          MapLayer.for_kind(kind)
        end

        def refuser_ailleurs!(objet, sauf: nil)
          raison = AILLEURS[objet.feature_kind]
          raise Error, "Pas ici : #{raison}." if raison && objet.feature_kind != sauf
          raise Error, "Les aménagements à l'essai et les croquis se gèrent sur la carte." if objet.map_layer&.design? || objet.map_layer&.kind == "sketch"
        end
      end
    end
  end
end
