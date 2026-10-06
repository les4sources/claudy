module Mcp
  module Tools
    module Carte
      # Carte > Carnet (MapTasksController#index) : les tâches de gestion de
      # l'année, mois par mois, sur les objets de la carte et les plantes.
      class CarnetTaches < Base
        include Commun

        tool "carnet_taches",
             title: "Carnet des tâches de la carte",
             description: "Les tâches qui reviennent chaque année (fauche, taille, entretien), mois par mois, avec leur " \
                          "porteur (plante ou objet de la carte). Défaut : les douze mois. Filtres : mois, filière.",
             schema: {
               properties: {
                 mois: MOIS.merge(description: "Les mois à montrer. Défaut : les douze, plus les tâches sans mois."),
                 filiere: { type: "string", enum: MapTask::SECTORS.keys, description: "terrain ou nourricier." }
               }
             }

        def call(arguments)
          mois = arguments["mois"].present? ? mois!(arguments["mois"]) : nil
          taches = MapTask.with_live_subject.in_sector(arguments["filiere"]).includes(:subject).order(:label, :id).to_a
          porteur = lambda do |tache|
            sujet = tache.subject
            sujet.is_a?(Plant) ? "plante #{nom_plante(sujet)}" : "objet ##{sujet.id} #{sujet.display_name.presence || 'sans nom'}"
          end
          ligne = ->(tache) { "  #{ligne_tache(tache)} — #{porteur.call(tache)}" }

          sections = (mois || MapTask::MONTHS).map do |m|
            du_mois = taches.select { |t| t.months.include?(m) }
            "#{MapTask.month_name(m)} : #{du_mois.empty? ? 'rien' : "\n#{du_mois.map(&ligne).join("\n")}"}"
          end
          sans_mois = taches.select { |t| t.months.empty? }
          sections << "Sans mois :\n#{sans_mois.map(&ligne).join("\n")}" if mois.nil? && sans_mois.any?
          "Carnet#{" — filière #{MapTask::SECTORS[arguments['filiere']]}" if arguments['filiere'].present?}\n#{sections.join("\n")}"
        end
      end
    end
  end
end
