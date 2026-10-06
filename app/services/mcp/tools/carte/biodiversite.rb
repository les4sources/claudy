module Mcp
  module Tools
    module Carte
      # Carte > Biodiversité (MapObservationsController#page) et les relevés
      # de plantes bio-indicatrices (MapBioindicatorsController#index).
      class Biodiversite < Base
        include Commun

        LIMITE = 200

        tool "biodiversite",
             title: "Relevés de biodiversité",
             description: "`quoi: observations` (défaut) : les relevés de flore, faune et fonge (#id, espèce, date, " \
                          "observateur, effectif, point GPS), filtrés par règne, espèce, année, et le nombre d'espèces " \
                          "distinctes. `quoi: bioindicatrices` : les relevés photo de plantes bio-indicatrices, leur " \
                          "statut d'analyse et les indicateurs trouvés.",
             schema: {
               properties: {
                 quoi: { type: "string", enum: %w[observations bioindicatrices] },
                 regne: { type: "string", description: MapFeatureObservation::REALMS.map { |k, v| "#{k} (#{v})" }.join(", ") },
                 espece: { type: "string", description: "Nom commun exact (casse ignorée)." },
                 annee: { type: "integer" },
                 statut: { type: "string", enum: MapFeatureBioindicator::BIOINDICATOR_STATUSES.keys,
                           description: "Bio-indicatrices : to_analyze ou analyzed." }
               }
             }

        def call(arguments)
          return bioindicatrices(arguments) if arguments["quoi"] == "bioindicatrices"

          regne = choix!(arguments["regne"], MapFeatureObservation::REALMS, "règne")
          scope = MapFeature.filter_observations(realm: regne, species: arguments["espece"], year: arguments["annee"])
          total = scope.count
          releves = scope.limit(LIMITE).to_a
          observateurs = User.where(id: releves.filter_map(&:observer_id)).index_by(&:id)
          entete = "#{total} relevé(s), #{MapFeature.distinct_species_count(scope)} espèce(s) distincte(s)" \
                   "#{" — les #{LIMITE} plus récents" if total > LIMITE}"
          return "#{entete}." if releves.empty?

          lignes = releves.map do |r|
            qui = observateurs[r.observer_id]&.display_name || r.observer_name || "—"
            "Relevé ##{r.id} #{r.observed_on ? I18n.l(r.observed_on) : '?'} · #{r.realm_label} · #{r.species_common}" \
              "#{" (#{r.species_latin})" if r.species_latin}#{" ×#{r.observation_count}" if r.observation_count} · #{qui} · " \
              "#{point(r)}#{' · importé' if r.imported?}"
          end
          "#{entete} :\n#{lignes.join("\n")}"
        end

        private

        def bioindicatrices(arguments)
          releves = MapFeature.filter_bioindicators(status: arguments["statut"]).limit(LIMITE).to_a
          return "Aucun relevé de bio-indicatrices." if releves.empty?

          releves.map do |r|
            indicateurs = r.analysis_indicators.first(4).map { |i| i[:label] || i[:key] }
            "Relevé ##{r.id} #{r.bioindicator_title} · #{r.bioindicator_status_label} · #{point(r)}" \
              "#{" · #{indicateurs.join(', ')}" if indicateurs.any?} · #{r.photos.size} photo(s)"
          end.join("\n")
        end
      end
    end
  end
end
