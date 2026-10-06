module Mcp
  module Tools
    module Carte
      # Les objets de la carte (MapsController#show, MapFeaturesController,
      # Maps::Search) : les couches, ce qu'elles portent, la recherche du mode
      # actif, et la fiche d'un objet.
      class ElementsCarte < Base
        include Commun

        LIMITE = 150

        tool "elements_carte",
             title: "Objets de la carte",
             description: "Sans argument : les couches de la carte et leur nombre d'objets. Avec `couche` : ses objets " \
                          "(#id, nom, type, point GPS, longueur d'un tracé), filtrés par `recherche` comme la recherche " \
                          "de la carte. Avec `element` : la fiche d'un objet (description, consignes, nature, nœud de " \
                          "réseau, lieux représentés, tâches, notes, fil de commentaires, relevé).",
             schema: {
               properties: {
                 couche: {
                   type: "string",
                   description: "Type de couche (#{MapLayer::KINDS.join(', ')}) ou son libellé, ou un réseau : " \
                                "#{MapLayer::NETWORKS.map { |k, v| "#{k} (#{v[:name]})" }.join(', ')}."
                 },
                 recherche: { type: "string", description: "Texte cherché dans les champs de la couche (nom, description, tâches, messages…)." },
                 element: ELEMENT
               }
             }

        def call(arguments)
          return fiche(element!(arguments["element"])) if arguments["element"].present?
          return couches if arguments["couche"].blank?

          couche = couche!(arguments["couche"])
          scope = couche.map_features.ordered.includes(:map_layer, :map_feature_venues, plant: %i[plant_species plant_variety])
          if arguments["recherche"].present?
            mode = couche.kind
            unless ::Maps::Search.supported?(mode)
              raise Error, "La couche #{couche.name} n'a pas de recherche ; modes : #{::Maps::Search::MODES.join(', ')}."
            end

            ids = ::Maps::Search.new(mode: mode, query: arguments["recherche"], layer_id: couche.id).feature_ids
            scope = scope.where(id: ids)
          end
          total = scope.count
          objets = scope.limit(LIMITE).to_a
          return "#{couche.name} : aucun objet#{' ne correspond' if arguments['recherche'].present?}." if objets.empty?

          "#{couche.name} (couche ##{couche.id}) : #{total} objet(s)#{" — les #{LIMITE} premiers" if total > LIMITE}\n" \
            "#{objets.map { |o| ligne_element(o) }.join("\n")}"
        end

        private

        # Les couches uniques sont créées à la demande, comme à l'ouverture de
        # la carte : on ne les crée pas ici, on lit ce qui existe.
        def couches
          lignes = MapLayer.ordered.map do |couche|
            "Couche ##{couche.id} #{couche.name} (#{couche.network.presence || couche.kind}) · #{couche.map_features.count} objet(s)"
          end
          "Couches de la carte :\n#{lignes.join("\n")}"
        end

        def couche!(reference)
          texte = I18n.transliterate(reference.to_s.strip).downcase
          reseau = MapLayer::NETWORKS.find { |cle, spec| cle == texte || I18n.transliterate(spec[:name]).downcase == texte }&.first
          if reseau
            return MapLayer.where(kind: "network").find { |c| c.network == reseau } ||
                   raise(Error, "Le réseau #{MapLayer::NETWORKS[reseau][:name]} n'a pas encore de couche : ouvre la carte une fois.")
          end

          kind = MapLayer::KINDS.find { |k| k == texte || I18n.transliterate(MapLayer::KIND_LABELS[k]).downcase == texte }
          raise Error, "Couche inconnue « #{reference} »." unless kind
          raise Error, "Il y a plusieurs couches #{kind} : précise le réseau (eau, électricité, ethernet, gaz)." if kind == "network"

          kind == "sketch" ? raise(Error, "Les notes manuscrites se lisent sur la carte.") : MapLayer.for_kind(kind)
        end

        def fiche(objet)
          lignes = [ligne_element(objet)]
          description = objet.description(:fr)
          lignes << "Description : #{description}" if description.present?
          traductions = %w[en nl].filter_map do |langue|
            nom = objet.name_i18n.to_h[langue].presence
            desc = objet.description_i18n.to_h[langue].presence
            "#{langue} : #{[nom, desc].compact.join(' — ')}" if nom || desc
          end
          lignes << "Traductions : #{traductions.join(' · ')}" if traductions.any?
          lignes << "À traduire : #{objet.missing_translations.join(', ')}" if objet.map_layer&.welcome? && objet.missing_translations.any?
          details = {
            "Nature" => MapFeature::ACCESS_LEVELS[objet.access], "Icône" => MapFeature::WELCOME_ICONS[objet.icon],
            "Consigne de gestion" => objet.management_notes, "Type de nœud" => objet.node_type_label,
            "Consigne" => objet.instructions, "Calibre" => MapFeature::GAUGES[objet.gauge],
            "Équipement" => MapFeature::EQUIPMENTS[objet.equipment], "Équipement UniFi" => objet.unifi_device_id,
            "Origine de l'eau" => objet.water_source_label, "Représente" => objet.venue_names
          }.compact_blank
          lignes.concat(details.map { |cle, valeur| "#{cle} : #{valeur}" })
          lignes << "Plante : #{ligne_plante(objet.plant)} (voir fiche_plante)" if objet.plant_point? && objet.plant
          lignes.concat(observation(objet)) if objet.observation_point?
          lignes.concat(bioindicateur(objet)) if objet.bioindicator_point?
          lignes.concat(fil(objet)) if objet.comment_point?
          lignes << "Photos : #{objet.photos.size}" if objet.photos.attached?
          taches = objet.map_tasks.ordered.to_a
          lignes << "Tâches :\n#{taches.map { |t| "  #{ligne_tache(t)}" }.join("\n")}" if taches.any?
          notes = objet.map_notes.includes(:author).limit(10).to_a
          lignes << "Notes datées :\n#{notes.map { |n| "  #{ligne_note(n)}" }.join("\n")}" if notes.any?
          lignes.join("\n")
        end

        def observation(objet)
          [
            "Relevé : #{objet.realm_label} · #{objet.species_common}#{" (#{objet.species_latin})" if objet.species_latin} · " \
            "#{objet.observed_on ? I18n.l(objet.observed_on) : 'date ?'} · par #{objet.observer&.display_name || objet.observer_name || '—'}" \
            "#{" · effectif #{objet.observation_count}" if objet.observation_count}",
            ("Importé de #{objet.properties['source']} : #{objet.source_url}" if objet.imported?)
          ].compact
        end

        def bioindicateur(objet)
          lignes = ["Bio-indicatrices : #{objet.bioindicator_status_label} · #{objet.bioindicator_title}"]
          return lignes unless objet.analyzed?

          indicateurs = objet.analysis_indicators.map { |i| "#{i[:label] || i[:key]} (#{i[:strength]}/3)" }
          lignes << "Indicateurs : #{indicateurs.join(', ')}" if indicateurs.any?
          lignes << "Agronomie : #{objet.analysis_agronomy.to_s.squish.truncate(400)}" if objet.analysis_agronomy.present?
          lignes
        end

        def fil(objet)
          racine = objet.map_comments.roots.first
          return ["Fil : vide"] unless racine

          messages = racine.thread.map { |c| "  Message ##{c.id} #{I18n.l(c.created_at.to_date)} #{c.author.display_name} : #{c.body.squish}" }
          ["Fil ##{racine.id} #{racine.resolved? ? 'résolu' : 'ouvert'} :", *messages]
        end
      end
    end
  end
end
