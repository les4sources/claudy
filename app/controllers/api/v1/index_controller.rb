module Api
  module V1
    # Discovery endpoint: a JSON "README" so an agent can learn the API surface
    # from a single GET, then fetch the full OpenAPI spec.
    class IndexController < BaseController
      def show
        render json: {
          name: "Claudy API",
          version: "v1",
          description: "API privée en lecture seule du Domaine d'Ahinvaux (Les 4 Sources). " \
                       "Donne à un agent IA l'accès aux réservations, disponibilités, catalogue " \
                       "(logements/chambres/espaces), à la vie du collectif et aux paiements.",
          authentication: {
            type: "bearer",
            header: "Authorization: Bearer <token>",
            note: "Le jeton est fourni hors-bande. Toutes les routes exigent ce header."
          },
          documentation: {
            openapi: api_v1_openapi_url(format: :json)
          },
          conventions: {
            format: "json",
            pagination: "Listes paginées : ?page=N&per_page=M (max 200, défaut 50). Méta dans `meta`.",
            dates: "Dates au format ISO 8601 (YYYY-MM-DD).",
            money: "Montants exposés en centimes (`cents`) + version formatée."
          },
          resources: [
            { name: "bookings", path: api_v1_bookings_path, description: "Réservations de séjour (logements). Filtres: from_date, to_date, status, lodging_id." },
            { name: "space_bookings", path: api_v1_space_bookings_path, description: "Réservations de salles/espaces. Filtres: from_date, to_date, status." },
            { name: "availability", path: api_v1_availability_path, description: "Disponibilité par logement/espace sur une plage de dates. Requiert ?from= & ?to=." },
            { name: "lodgings", path: api_v1_lodgings_path, description: "Catalogue des hébergements (prix, chambres, description)." },
            { name: "rooms", path: api_v1_rooms_path, description: "Chambres rattachées aux hébergements." },
            { name: "spaces", path: api_v1_spaces_path, description: "Espaces/salles louables." },
            { name: "humans", path: api_v1_humans_path, description: "Membres du collectif." },
            { name: "cycles", path: api_v1_cycles_path, description: "Cycles de l'organisation (périodes datées)." },
            { name: "cycle_actions", path: api_v1_cycle_actions_path, description: "Actions de cycle par membre. Filtres: human_id, category, completed." },
            { name: "tasks", path: api_v1_tasks_path, description: "Tâches de l'organisation. Filtres: status, project_id." },
            { name: "payments", path: api_v1_payments_path, description: "Paiements liés aux réservations (identifiants Stripe non exposés)." }
          ],
          example: "curl -H 'Authorization: Bearer $AGENT_API_TOKEN' #{api_v1_bookings_url}"
        }
      end
    end
  end
end
