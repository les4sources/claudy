module Mcp
  module Tools
    module Collectif
      # Le registre des décisions (DecisionsController : create, update, destroy).
      class EnregistrerDecision < Ecriture
        include Commun

        tool "enregistrer_decision",
             title: "Inscrire, corriger ou retirer une décision",
             description: "Sans `decision` : inscrit une décision au registre (titre, résumé, texte complet, date, " \
                          "rassemblement et point d'ordre du jour d'où elle vient) ; tu en es le rédacteur. Avec : " \
                          "corrige ce qui est donné. Avec supprimer (motif obligatoire) : la retire du registre.",
             schema: {
               properties: {
                 decision: DECISION,
                 titre: { type: "string" },
                 resume: { type: "string", description: "Une ou deux phrases." },
                 texte: TEXTE.merge(description: "Le texte complet (remplace l'actuel)."),
                 date: DATE.merge(description: "Date de la décision. Défaut : celle du rassemblement, sinon aujourd'hui."),
                 rassemblement: RASSEMBLEMENT,
                 point: { type: %w[integer string], description: "Point de l'ordre du jour (#88) dont elle découle." },
                 supprimer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          decision = arguments["decision"].present? ? decision!(arguments["decision"]) : nil
          return plan_suppression(decision) if arguments["supprimer"]

          attributs = attributs(arguments, decision)
          raise Error, "Rien à changer." if decision && attributs.empty?

          apercu = simuler { enregistrer(decision && Decision.find(decision.id), attributs) }
          resume = [decision && "Avant : #{ligne_decision(decision)}", "#{decision ? 'Après' : 'Inscrire'} : #{apercu}",
                    decision ? nil : "Rédacteur : #{moi!.name}"].compact
          resume << "Texte complet remplacé." if decision && attributs.key?(:body)
          Plan.new(resume: resume.join("\n"), empreinte: [decision && etat_de(decision), signature(arguments)],
                   donnees: { id: decision&.id, attributs: attributs })
        end

        def appliquer(plan)
          if plan.donnees[:supprimer]
            Decision.find(plan.donnees[:supprimer]).soft_delete!(validate: false)
            return "Décision ##{plan.donnees[:supprimer]} retirée du registre (suppression douce)."
          end

          id = plan.donnees[:id]
          "Décision enregistrée : #{enregistrer(id && Decision.find(id), plan.donnees[:attributs])}"
        end

        def enregistrer(decision, attributs)
          params = ActionController::Parameters.new(decision: attributs)
          service = decision ? Decisions::UpdateService.new(decision: decision) : Decisions::CreateService.new(recorded_by: moi!)
          service! { service.run!(params) }
          ligne_decision(service.decision)
        rescue ActiveRecord::RecordInvalid => e
          raise Error, e.record.errors.full_messages.to_sentence
        end

        def attributs(arguments, decision)
          attributs = {}
          attributs[:title] = arguments["titre"].to_s.strip if arguments["titre"].present?
          attributs[:summary] = arguments["resume"].to_s.strip if arguments["resume"].present?
          attributs[:body] = html(arguments["texte"]) if arguments.key?("texte")
          gathering = arguments["rassemblement"].present? ? rassemblement!(arguments["rassemblement"]) : nil
          attributs[:gathering_id] = gathering.id if gathering
          if arguments["point"].present?
            point = AgendaItem.find_by(id: id!(arguments["point"], "point")) || raise(Error, "Aucun point ##{arguments['point']}.")
            attributs[:agenda_item_id] = point.id
            attributs[:gathering_id] ||= point.gathering_id
          end
          if arguments["date"].present?
            attributs[:taken_at] = date!(arguments["date"], "date").iso8601
          elsif decision.nil?
            date = (gathering || (attributs[:gathering_id] && Gathering.find(attributs[:gathering_id])))&.starts_at&.to_date
            attributs[:taken_at] = (date || Date.current).iso8601
          end
          if decision.nil? && (attributs[:title].blank? || attributs[:summary].blank?)
            raise Error, "Une décision demande un titre et un résumé."
          end

          attributs
        end

        def plan_suppression(decision)
          raise Error, "Donne la décision à retirer." unless decision

          motif!({ "motif" => @motif })
          Plan.new(resume: "RETIRER du registre : #{ligne_decision(decision)}", empreinte: [etat_de(decision), :supprimer],
                   donnees: { supprimer: decision.id })
        end
      end
    end
  end
end
