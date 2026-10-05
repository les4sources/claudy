module Mcp
  module Tools
    module Cuisine
      # La page Cuisine (Kitchen::OrdersController#index) et ses onglets.
      class PrestationsCuisine < Base
        include Commun

        VUES = {
          "prochains" => "accepté par la cuisine, non annulé, daté et à venir (défaut)",
          "a_venir" => "tout ce qui est à venir et pas annulé, hors demandes d'info",
          "cuisine" => "la cuisine a la main : pas encore répondu, ou personne ne s'en charge",
          "accueil" => "l'accueil a la main : client à relancer, ou refus de la cuisine à couvrir",
          "info" => "demandes d'info à venir",
          "archives" => "déjà servi (12 derniers mois)",
          "annulees" => "annulé par le client, ou refusé par la cuisine et passé",
          "toutes" => "tout, filtré par séjour, membre ou période"
        }.freeze

        tool "prestations_cuisine",
             title: "Prestations de la cuisine",
             description: "Liste les prestations de cuisine (repas, goûters, buffets, apéros ; une ligne = un service) " \
                          "selon les onglets de la page Cuisine : #{VUES.map { |cle, sens| "#{cle} (#{sens})" }.join(' ; ')}. " \
                          "Filtrable par famille, responsable, séjour et période.",
             schema: {
               properties: {
                 vue: { type: "string", enum: VUES.keys, description: "Onglet. Défaut : prochains." },
                 famille: FAMILLE,
                 responsable: MEMBRE.merge(description: "Ne garder que les prestations de ce membre (nom, ou « moi »)."),
                 origine: { type: "string", enum: MealOrder::ORIGINS, description: "client (funnel) ou reception (saisie de l'accueil)." },
                 sejour: { type: %w[integer string], description: "Identifiant du séjour (#1234)." },
                 du: DATE.merge(description: "Services à partir de cette date."),
                 au: DATE.merge(description: "Services jusqu'à cette date.")
               }
             }

        LIMITE = 150

        def call(arguments)
          vue = arguments["vue"].presence || "prochains"
          lignes = filtrer(base(arguments), vue, arguments)
          return "Aucune prestation (#{vue})." if lignes.empty?

          tronque = lignes.size > LIMITE
          lignes = lignes.first(LIMITE)
          facturable = lignes.select(&:billable?).sum { |o| o.price_cents.to_i }
          entete = "#{lignes.size} prestation(s), vue #{vue}#{" (limité à #{LIMITE})" if tronque} · " \
                   "#{lignes.sum(&:people)} couverts · facturable #{euros(facturable)} :"
          corps = lignes.map do |order|
            [ligne_prestation(order), *avertissements(order).map { |a| "   #{a}" }].join("\n")
          end
          "#{entete}\n#{corps.join("\n")}"
        end

        private

        def base(arguments)
          scope = MealOrder.includes(:responsible_human, stay: :customer)
          scope = scope.of_family(arguments["famille"]) if arguments["famille"].present?
          scope = scope.where(responsible_human_id: membre!(arguments["responsable"]).id) if arguments["responsable"].present?
          scope = scope.of_origin(arguments["origine"]) if arguments["origine"].present?
          if arguments["sejour"].present?
            scope = scope.where(stay_id: Integer(arguments["sejour"].to_s.delete("#"), exception: false) || 0)
          end
          du = date_ou_nil(arguments["du"], "du")
          au = date_ou_nil(arguments["au"], "au")
          scope = scope.where(date: du..) if du
          scope = scope.where(date: ..au) if au
          scope
        end

        def filtrer(scope, vue, arguments)
          vivantes = -> { scope.upcoming.where.not(status: "cancelled").undated_first.to_a }
          case vue
          when "prochains"
            scope.where(validation: "accepted").where.not(status: "cancelled").where(date: Date.current..).order(:date, :id).to_a
          when "a_venir" then vivantes.call.reject(&:inquiry?)
          when "cuisine" then vivantes.call.select { |o| o.next_actor == :kitchen }
          when "accueil" then vivantes.call.select { |o| %i[reception to_cover].include?(o.next_actor) }
          when "info" then vivantes.call.select(&:inquiry?)
          when "archives"
            archives = scope.past.where.not(status: "cancelled").where.not(validation: "refused")
            archives = archives.where(date: 12.months.ago.to_date..) if arguments["du"].blank?
            archives.antichronological.limit(LIMITE + 1).to_a
          when "annulees"
            scope.where(status: "cancelled").or(scope.past.where(validation: "refused")).antichronological.limit(LIMITE + 1).to_a
          else scope.chronological.limit(LIMITE + 1).to_a
          end
        end
      end
    end
  end
end
