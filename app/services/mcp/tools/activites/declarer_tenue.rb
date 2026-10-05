module Mcp
  module Tools
    module Activites
      # La file « Tenue à déclarer » : a eu lieu / n'a pas eu lieu. C'est ce qui
      # ouvre la rémunération du porteur au relevé trimestriel.
      class DeclarerTenue < Ecriture
        include Commun

        tool "declarer_tenue",
             title: "Déclarer la tenue d'activités",
             description: "Déclare qu'une ou plusieurs activités confirmées et passées ont eu lieu (held) ou non (no_show). " \
                          "« A eu lieu » ouvre la rémunération du porteur. Une fois déclarée, la tenue ne change plus. Aucun email.",
             schema: {
               properties: {
                 reservations: { type: "array", items: { type: %w[integer string] }, description: "Identifiants des réservations." },
                 tenue: { type: "string", enum: ExperienceBooking::OUTCOMES, description: "held (a eu lieu) ou no_show." }
               },
               required: %w[reservations tenue]
             }

        private

        def planifier(arguments)
          tenue = arguments["tenue"].to_s
          raise Error, "tenue : held ou no_show." unless ExperienceBooking::OUTCOMES.include?(tenue)

          liste = Array(arguments["reservations"]).map { |id| reservation!(id) }.uniq
          raise Error, "Donne au moins une réservation." if liste.empty?

          equipe! if liste.size > 1
          refus = liste.filter_map do |resa|
            next "##{resa.id} : déjà déclarée (#{resa.outcome_label})" if resa.outcome_recorded?
            next "##{resa.id} : pas confirmée" unless resa.confirmed?
            next "##{resa.id} : le créneau n'a pas encore eu lieu" if resa.slot_in_the_future?
          end
          raise Error, "Impossible de déclarer : #{refus.join(' ; ')}." if refus.any?

          Plan.new(resume: "#{ExperienceBooking::OUTCOME_LABELS[tenue]} pour :\n#{liste.map { |r| "- #{ligne_reservation(r)}" }.join("\n")}",
                   empreinte: [liste.map(&:id).sort, tenue], donnees: { ids: liste.map(&:id), tenue: tenue })
        end

        def appliquer(plan)
          plan.donnees[:ids].each { |id| reservation!(id).record_outcome!(plan.donnees[:tenue], by: user.human) }
          "#{plan.donnees[:ids].size} réservation(s) déclarée(s) : #{ExperienceBooking::OUTCOME_LABELS[plan.donnees[:tenue]]}."
        end
      end
    end
  end
end
