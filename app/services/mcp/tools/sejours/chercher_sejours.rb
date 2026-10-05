module Mcp
  module Tools
    module Sejours
      class ChercherSejours < Base
        include Commun

        tool "chercher_sejours",
             title: "Chercher des séjours",
             description: "Liste les séjours (réservations) avec leurs dates, le client, le statut, le total, ce qui " \
                          "est payé et ce qui reste dû. Sans critère : les séjours à venir. La recherche porte sur le " \
                          "client (nom, e-mail), le nom du groupe et les notes internes, sur toute la période.",
             schema: {
               properties: {
                 recherche: { type: "string", description: "Nom, e-mail, groupe ou mot de la note (2 caractères au moins)." },
                 statut: { type: "string", enum: %w[pending pre_confirmed confirmed canceled],
                           description: "pending (en attente), pre_confirmed (acompte demandé), confirmed, canceled." },
                 du: DATE.merge(description: "Séjours présents à partir de cette date (AAAA-MM-JJ)."),
                 au: DATE.merge(description: "Séjours présents jusqu'à cette date (AAAA-MM-JJ)."),
                 passes: { type: "boolean", description: "Sans dates ni recherche : les séjours passés plutôt qu'à venir." },
                 reste_du: { type: "boolean", description: "Seulement les séjours qui ont encore un solde à payer." },
                 limite: { type: "integer", description: "50 par défaut, 200 au plus." }
               }
             }

        def call(arguments)
          du = date_ou_nil(arguments["du"], "du")
          au = date_ou_nil(arguments["au"], "au")
          recherche = arguments["recherche"].to_s.strip
          limite = (arguments["limite"].presence || 50).to_i.clamp(1, 200)

          scope = Stay.all
          scope = scope.where("departure_date >= ?", du) if du
          scope = scope.where("arrival_date <= ?", au) if au
          if du.nil? && au.nil? && recherche.length < Stays::Search::MIN_LENGTH
            scope = arguments["passes"] ? scope.where("departure_date < ?", Date.current) : scope.where("departure_date >= ? OR departure_date IS NULL", Date.current)
          end
          if arguments["statut"].present?
            statuts = arguments["statut"] == "canceled" ? Stay::CANCELED_STATUSES : [arguments["statut"]]
            scope = scope.where(status: statuts)
          end

          ordre = arguments["passes"] ? "arrival_date DESC NULLS LAST, id DESC" : "arrival_date ASC NULLS LAST, id ASC"
          sejours = Stays::Search.new(scope, recherche).call
                                 .includes(:customer, :meal_orders, :linen_orders, { stay_items: :bookable }, :experience_bookings)
                                 .order(Arel.sql(ordre)).limit(limite).to_a
          montants = Stays::IndexAmounts.new(sejours).call
          sejours = sejours.select { |s| montants[s.id].balance_due_cents.positive? } if arguments["reste_du"]
          return "Aucun séjour trouvé." if sejours.empty?

          lignes = sejours.map { |stay| ligne_sejour(stay, montants[stay.id]) }
          "#{sejours.size} séjour(s)#{" (limité à #{limite})" if sejours.size == limite} :\n#{lignes.join("\n")}"
        end
      end
    end
  end
end
