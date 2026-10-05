module Mcp
  module Tools
    module Sejours
      # « Supprimer le séjour » (`Stays::DestroyService`) : mise au rebut, pas
      # de destruction. Ses occupations libèrent le calendrier ; ses paiements
      # restent.
      class SupprimerSejour < Ecriture
        include Commun

        tool "supprimer_sejour",
             title: "Supprimer un séjour",
             description: "Supprime un séjour (réversible en base, tracé) : il quitte le calendrier, ses activités et " \
                          "repas sont annulés (la cuisine est prévenue), ses paiements sont conservés. Le client " \
                          "n'est pas prévenu. Pour une demande refusée, préfère refuser_sejour ; pour un séjour " \
                          "annulé qui doit rester visible, changer_statut_sejour.",
             schema: { properties: { sejour: SEJOUR }, required: %w[sejour] }

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          motif!(arguments)
          effets = []
          effets << "#{stay.experience_bookings.active.count} activité(s) annulée(s)" if stay.experience_bookings.active.any?
          effets << "#{stay.meal_orders.active.count} repas annulé(s), la cuisine est prévenue" if stay.meal_orders.active.any?
          paiements = stay.payments.paid.sum(:amount_cents)
          effets << "#{euros(paiements)} de paiements reçus restent enregistrés" if paiements.positive?
          Plan.new(resume: "Suppression de : #{ligne_sejour(stay)}\n#{effets.join(' · ')}".strip,
                   empreinte: etat(stay), donnees: { stay_id: stay.id })
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          Stays::DestroyService.new(stay: stay).run
          "Séjour ##{stay.id} supprimé."
        end
      end
    end
  end
end
