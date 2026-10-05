module Mcp
  module Tools
    module Activites
      # L'écran « Réservations d'activités » et la file « Tenue à déclarer ».
      class ReservationsActivites < Base
        include Commun

        tool "reservations_activites",
             title: "Réservations d'activités",
             description: "Liste les réservations d'activités : à valider par le porteur, confirmées, refusées, " \
                          "annulées, ou dont la tenue reste à déclarer (créneau passé, ni « a eu lieu » ni « n'a pas " \
                          "eu lieu »). Filtrable par activité et par période.",
             schema: {
               properties: {
                 file: { type: "string", enum: %w[a_valider tenue_a_declarer toutes],
                         description: "a_valider (défaut), tenue_a_declarer, ou toutes." },
                 statut: { type: "string", enum: ExperienceBooking::STATUSES, description: "Avec file « toutes »." },
                 activite: ACTIVITE,
                 du: DATE.merge(description: "Créneaux à partir de cette date."),
                 au: DATE.merge(description: "Créneaux jusqu'à cette date.")
               }
             }

        LIMITE = 100

        def call(arguments)
          scope = ExperienceBooking.for_user(user).joins(:experience_availability)
                                   .includes(stay: :customer, experience_availability: :experience)
          scope = case arguments["file"].presence || "a_valider"
                  when "a_valider" then scope.pending
                  when "tenue_a_declarer" then scope.awaiting_outcome
                  else arguments["statut"].present? ? scope.where(status: arguments["statut"]) : scope
                  end
          scope = scope.where(experience_availabilities: { experience_id: activite!(arguments["activite"]).id }) if arguments["activite"].present?
          du = date_ou_nil(arguments["du"], "du")
          au = date_ou_nil(arguments["au"], "au")
          scope = scope.where(experience_availabilities: { available_on: du.. }) if du
          scope = scope.where(experience_availabilities: { available_on: ..au }) if au

          liste = scope.order("experience_availabilities.available_on, experience_availabilities.starts_at").limit(LIMITE).to_a
          return "Aucune réservation d'activité." if liste.empty?

          "#{liste.size} réservation(s)#{" (limité à #{LIMITE})" if liste.size == LIMITE} :\n" \
            "#{liste.map { |resa| ligne_reservation(resa) }.join("\n")}"
        end
      end
    end
  end
end
