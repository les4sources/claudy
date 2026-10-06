module Mcp
  module Tools
    module Carte
      # Un relevé de biodiversité (MapObservationsController#create, #update,
      # MapFeaturesController#destroy) : une plante vue, un animal croisé, à un
      # endroit et un jour.
      class ReleveBiodiversite < Ecriture
        include Commun

        tool "releve_biodiversite",
             title: "Relevé de biodiversité",
             description: "`creer` un relevé (point GPS, règne, espèce, date, observateur, effectif, description), le " \
                          "`modifier` ou le `supprimer` (motif obligatoire). Les photos s'ajoutent dans Claudy. Pour " \
                          "reprendre le nom d'une espèce déjà relevée : biodiversite.",
             schema: {
               properties: {
                 geste: { type: "string", enum: %w[creer modifier supprimer] },
                 releve: { type: %w[integer string], description: "Le relevé (#id), pour modifier ou supprimer." },
                 latitude: LATITUDE,
                 longitude: LONGITUDE,
                 regne: { type: "string", description: MapFeatureObservation::REALMS.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 espece: { type: "string", description: "Nom commun (« Chevêche d'Athéna »)." },
                 nom_latin: { type: "string" },
                 date: DATE.merge(description: "Date d'observation (défaut : aujourd'hui ; jamais future)."),
                 observateur: { type: "string", description: "« moi » (défaut), un e-mail ou le nom d'un membre." },
                 effectif: { type: %w[integer string] },
                 description: TEXTE
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          case arguments["geste"]
          when "creer"
            lat, lng = coordonnees!(arguments["latitude"], arguments["longitude"])
            donnees = { geste: "creer", lat: lat, lng: lng, champs: champs!(arguments, creation: true) }
            Plan.new(resume: "Nouveau relevé en (#{lat}, #{lng}) :\n#{simuler { ecrire(donnees) }}",
                     empreinte: [signature(arguments)], donnees: donnees)
          when "modifier"
            releve = releve!(arguments["releve"])
            champs = champs!(arguments, creation: false)
            raise Error, "Rien à modifier." if champs.values.all?(&:empty?)

            donnees = { geste: "modifier", id: releve.id, champs: champs }
            Plan.new(resume: "Modifier le relevé ##{releve.id}\nAvant : #{ligne(releve)}\nAprès : #{simuler { ecrire(donnees) }}",
                     empreinte: [etat_de(releve), signature(arguments)], donnees: donnees)
          when "supprimer"
            releve = releve!(arguments["releve"])
            motif!({ "motif" => @motif })
            Plan.new(resume: "SUPPRIMER le relevé ##{releve.id} : #{ligne(releve)}", empreinte: [etat_de(releve)],
                     donnees: { geste: "supprimer", id: releve.id })
          else
            raise Error, "geste : creer, modifier ou supprimer."
          end
        end

        def appliquer(plan)
          if plan.donnees[:geste] == "supprimer"
            releve = MapFeature.observations.find(plan.donnees[:id])
            releve.soft_delete!(validate: false)
            return "Relevé ##{releve.id} supprimé."
          end

          "Relevé enregistré : #{ecrire(plan.donnees)}"
        end

        def ecrire(d)
          releve = if d[:geste] == "creer"
                     MapLayer.for_kind(:biodiversity).map_features.new(
                       feature_kind: "observation", created_by: user,
                       geometry: { "type" => "Point", "coordinates" => [d[:lng], d[:lat]] },
                       properties: { "observed_on" => Date.current.iso8601, "observer_id" => user.id }
                     )
                   else
                     MapFeature.observations.find(d[:id])
                   end
          releve.observation_attributes = d[:champs][:proprietes]
          if d[:champs][:description]
            releve.description_i18n = releve.description_i18n.to_h.merge("fr" => d[:champs][:description].first.to_s)
          end
          valide!(releve)
          releve.save!
          "##{releve.id} #{ligne(releve)}"
        end

        # Les clés d'un relevé, comme la fiche les envoie ; une chaîne vide
        # efface un champ facultatif.
        def champs!(arguments, creation:)
          proprietes = {}
          proprietes["realm"] = choix!(arguments["regne"], MapFeatureObservation::REALMS, "règne") if arguments.key?("regne")
          proprietes["species_common"] = arguments["espece"].to_s if arguments.key?("espece")
          proprietes["species_latin"] = arguments["nom_latin"].to_s if arguments.key?("nom_latin")
          proprietes["observed_on"] = date!(arguments["date"], "date").iso8601 if arguments["date"].present?
          proprietes["observer_id"] = utilisateur!(arguments["observateur"]).id if arguments.key?("observateur")
          proprietes["count"] = arguments["effectif"].to_s if arguments.key?("effectif")
          proprietes["observer_id"] ||= user.id if creation
          { proprietes: proprietes, description: (arguments.key?("description") ? [arguments["description"].to_s.strip] : []) }
        end

        def releve!(reference)
          MapFeature.observations.find_by(id: id!(reference, "relevé")) ||
            raise(Error, "Aucun relevé de biodiversité ##{reference.to_s.delete('#')}.")
        end

        def ligne(releve)
          [releve.realm_label, releve.species_common, (releve.species_latin && "(#{releve.species_latin})"),
           (releve.observed_on && I18n.l(releve.observed_on)), "par #{releve.observer&.display_name || releve.observer_name || '—'}",
           (releve.observation_count && "×#{releve.observation_count}"), point(releve),
           releve.description(:fr).presence&.then { |d| "« #{d.squish.truncate(120)} »" }].compact.join(" · ")
        end
      end
    end
  end
end
