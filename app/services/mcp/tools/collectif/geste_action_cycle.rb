module Mcp
  module Tools
    module Collectif
      # Les boutons d'une ligne d'action de cycle (CycleActionsController) et le
      # tri de la page de clôture.
      class GesteActionCycle < Ecriture
        include Commun

        GESTES = {
          "cocher" => "cocher faite (toutes ses fois)",
          "decocher" => "décocher",
          "fois_plus" => "cocher une fois de plus (action répétée)",
          "fois_moins" => "décocher une fois",
          "heure_reelle_plus" => "ajouter une heure réelle",
          "heure_reelle_moins" => "retirer une heure réelle",
          "mettre_en_attente" => "la mettre dans « reportée » (hors heures engagées du cycle)",
          "passer_au_suivant" => "la passer au cycle suivant (le reste à faire part là-bas)",
          "annuler_passage" => "annuler un passage au cycle suivant",
          "copier_au_suivant" => "la copier au cycle suivant, ou retirer la copie si elle existe",
          "basculer_economique" => "basculer activité économique / temps collectif",
          "archiver" => "l'archiver (faite si cochée, sinon abandonnée)",
          "desarchiver" => "la sortir des archives",
          "supprimer" => "la supprimer (motif obligatoire)"
        }.freeze

        # Les gestes que l'interface permet aussi sur un cycle clos.
        SUR_CYCLE_CLOS = %w[annuler_passage].freeze

        tool "geste_action_cycle",
             title: "Geste sur une action de cycle",
             description: "Un geste sur une action de cycle : #{GESTES.map { |cle, sens| "#{cle} (#{sens})" }.join(' ; ')}.",
             schema: {
               properties: { action: ACTION_CYCLE, geste: { type: "string", enum: GESTES.keys } },
               required: %w[action geste]
             }

        private

        def planifier(arguments)
          action = action_cycle!(arguments["action"])
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.keys.join(', ')}." unless GESTES.key?(geste)

          ouvert!(action.cycle) unless SUR_CYCLE_CLOS.include?(geste)
          motif!({ "motif" => @motif }) if geste == "supprimer"
          verifier_geste!(action, geste)

          apres = simuler { faire(CycleAction.find(action.id), geste) } unless geste == "supprimer"
          resume = ["Avant : #{ligne_action_cycle(action)}", "Geste : #{GESTES[geste]}"]
          resume << "Après : #{apres}" if apres
          Plan.new(resume: resume.join("\n"), empreinte: [etat_de(action), geste], donnees: { id: action.id, geste: geste })
        end

        def appliquer(plan)
          faire(CycleAction.find(plan.donnees[:id]), plan.donnees[:geste])
        end

        def verifier_geste!(action, geste)
          case geste
          when "cocher" then raise Error, "Elle est déjà cochée." if action.completed?
          when "decocher" then raise Error, "Elle n'est pas cochée." unless action.completed?
          when "fois_plus" then raise Error, "Toutes ses fois sont déjà faites." if action.completed_occurrences.to_i >= action.occurrences.to_i
          when "fois_moins" then raise Error, "Aucune fois n'est cochée." if action.completed_occurrences.to_i.zero?
          when "heure_reelle_moins" then raise Error, "Aucune heure réelle à retirer." unless action.actual_hours_recorded?
          when "mettre_en_attente" then raise Error, "Elle est déjà dans « reportée »." if action.reportee?
          when "passer_au_suivant", "archiver" then raise Error, "Elle est déjà tranchée." unless action.live?
          when "annuler_passage" then raise Error, "Elle n'a pas été passée au cycle suivant." unless action.outcome_deferred? && action.deferred_to
          when "desarchiver" then raise Error, "Elle n'est pas archivée." unless action.archived?
          end
        end

        def faire(action, geste)
          case geste
          when "cocher" then action.update!(completed: true)
          when "decocher" then action.update!(completed: false)
          when "fois_plus", "fois_moins"
            pas = geste == "fois_plus" ? 1 : -1
            action.update!(completed_occurrences: (action.completed_occurrences.to_i + pas).clamp(0, action.occurrences.to_i))
          when "heure_reelle_plus" then action.add_actual_hour!
          when "heure_reelle_moins" then action.remove_actual_hour!
          when "mettre_en_attente" then action.update!(category: :reportee)
          when "basculer_economique" then action.update!(economic: !action.economic?)
          when "archiver" then action.archive!
          when "desarchiver" then action.unarchive!
          when "passer_au_suivant"
            service = CycleActions::DeferService.new(cycle_action: action)
            service! { service.run! }
            return "#{ligne_action_cycle(action.reload)} → copie ##{service.copy.id} dans « #{service.target_cycle.name} »"
          when "annuler_passage"
            CycleAction.transaction do
              action.deferred_to&.soft_delete!(validate: false)
              action.update!(outcome: nil)
            end
          when "copier_au_suivant"
            service = CycleActions::CopyService.new(cycle_action: action)
            service! { service.run! }
            return "#{ligne_action_cycle(action.reload)} → #{service.copied? ? 'copiée dans' : 'copie retirée de'} « #{service.target_cycle.name} »"
          when "supprimer"
            action.soft_delete!(validate: false)
            return "Action ##{action.id} supprimée (suppression douce)."
          end
          ligne_action_cycle(action.reload)
        end
      end
    end
  end
end
