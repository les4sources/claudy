module Mcp
  module Tools
    module Activites
      # Supprimer un créneau. L'écran le fait même s'il porte des réservations
      # (elles disparaissent avec lui, sans que le total des séjours suive) :
      # ici on refuse tant qu'une réservation vivante y est accrochée.
      class SupprimerCreneau < Ecriture
        include Commun

        tool "supprimer_creneau",
             title: "Supprimer un créneau d'activité",
             description: "Supprime un créneau sans réservation en cours. S'il en porte, retire ou refuse d'abord ces " \
                          "réservations (annuler_reservation_activite, refuser_reservation_activite). Aucun email.",
             schema: { properties: { creneau: CRENEAU }, required: %w[creneau] }

        private

        def planifier(arguments)
          creneau = creneau!(arguments["creneau"])
          vivantes = creneau.experience_bookings.active.to_a
          if vivantes.any?
            raise Error, "Ce créneau porte #{vivantes.size} réservation(s) en cours (#{vivantes.map { |r| "##{r.id}" }.join(', ')}) : " \
                         "annule-les ou refuse-les d'abord."
          end

          Plan.new(resume: "Suppression du #{ligne_creneau(creneau)}", empreinte: [creneau.id, creneau.updated_at.to_f],
                   donnees: { id: creneau.id })
        end

        def appliquer(plan)
          creneau = creneau!(plan.donnees[:id])
          raise Error, "Une réservation vient d'arriver sur ce créneau : rien n'a été supprimé." if creneau.experience_bookings.active.exists?

          creneau.destroy!
          "Créneau ##{plan.donnees[:id]} supprimé."
        end
      end
    end
  end
end
