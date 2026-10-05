module Mcp
  module Tools
    module Activites
      # Le formulaire d'une activité (Experiences::CreateService / UpdateService) :
      # sans `activite`, on en crée une ; avec, on la modifie.
      class EnregistrerActivite < Ecriture
        include Commun

        CHAMPS = {
          "nom" => :name, "resume" => :summary, "prix_par_personne" => :price, "prix_fixe" => :fixed_price,
          "participants_min" => :min_participants, "participants_max" => :max_participants, "duree" => :duration,
          "duree_heures" => :duration_hours, "tarif_porteur_horaire" => :carrier_hourly_rate
        }.freeze

        tool "enregistrer_activite",
             title: "Créer ou modifier une activité",
             description: "Crée une activité (sans `activite`) ou modifie la fiche d'une activité existante : nom, " \
                          "porteur, résumé, description, prix par personne et prix fixe (euros TTC), participants, " \
                          "durée affichée, durée en heures (base de la rémunération), tarif horaire propre du porteur. " \
                          "Aucun email ; une activité publiée met le site à jour.",
             schema: {
               properties: {
                 activite: ACTIVITE.merge(description: "L'activité à modifier. Absente : création."),
                 nom: { type: "string" }, porteur: { type: "string", description: "Nom du membre qui porte l'activité." },
                 resume: { type: "string" }, description: { type: "string", description: "Texte de présentation (remplace l'actuel)." },
                 prix_par_personne: { type: %w[number string] }, prix_fixe: { type: %w[number string] },
                 participants_min: { type: "integer" }, participants_max: { type: "integer" },
                 duree: { type: "string", description: "Durée affichée, « 2 h »." },
                 duree_heures: { type: %w[number string], description: "Heures payées au porteur." },
                 tarif_porteur_horaire: { type: %w[number string], description: "Euros de l'heure ; vide = tarif par défaut." }
               }
             }

        private

        def planifier(arguments)
          equipe!
          activite = arguments["activite"].present? ? activite!(arguments["activite"]) : nil
          attributs = CHAMPS.each_with_object({}) do |(cle, champ), acc|
            acc[champ] = arguments[cle].to_s.strip.tr(",", ".") if arguments.key?(cle)
          end
          attributs[:human_id] = porteur!(arguments["porteur"])&.id if arguments.key?("porteur")
          attributs[:description] = Stays::InternalNote.to_html(arguments["description"]) if arguments.key?("description")
          raise Error, "Rien à enregistrer : donne au moins un champ." if attributs.empty?
          raise Error, "Une nouvelle activité a besoin d'un nom." if activite.nil? && attributs[:name].blank?

          essai = activite ? Experience.find(activite.id) : Experience.new
          avant = activite ? resume(essai) : nil
          essai.assign_attributes(attributs)
          raise Error, "Fiche refusée : #{essai.errors.full_messages.to_sentence}" unless essai.valid?

          Plan.new(resume: activite ? "Activité ##{activite.id}\nAvant : #{avant}\nAprès : #{resume(essai)}" : "Nouvelle activité : #{resume(essai)}",
                   empreinte: [activite&.id, activite&.updated_at&.to_f, attributs.transform_values(&:to_s)],
                   donnees: { id: activite&.id, attributs: attributs })
        end

        def appliquer(plan)
          parametres = ActionController::Parameters.new(experience: plan.donnees[:attributs])
          service = plan.donnees[:id] ? Experiences::UpdateService.new(experience: activite!(plan.donnees[:id])) : Experiences::CreateService.new
          raise Error, service.error_message(default: "L'activité n'a pas pu être enregistrée.") unless service.run(parametres)

          "Activité ##{service.experience.id} enregistrée : #{resume(service.experience)}."
        end

        def resume(activite)
          "#{activite.name} · porteur #{activite.human&.name || 'aucun'} · #{Pricing::ExperienceLine.rate_label(activite)} · " \
            "#{activite.min_participants || '?'}–#{activite.max_participants || '∞'} pers. · #{activite.duration.presence || 'durée ?'}" \
            "#{" (#{activite.duration_hours} h payées)" if activite.duration_hours}" \
            "#{" · porteur à #{euros(activite.carrier_hourly_rate_cents)}/h" if activite.carrier_hourly_rate_cents}"
        end
      end
    end
  end
end
