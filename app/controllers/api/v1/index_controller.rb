module Api
  module V1
    # Discovery endpoint: a JSON "README" so an agent can learn the API surface
    # from a single GET, then fetch the full OpenAPI spec.
    class IndexController < BaseController
      def show
        render json: {
          name: "Claudy API",
          version: "v1",
          description: "API privée du Domaine d'Ahinvaux (Les 4 Sources). Donne à un agent IA " \
                       "l'accès en lecture aux réservations, disponibilités, catalogue " \
                       "(logements/chambres/espaces), à la vie du collectif et aux paiements, " \
                       "ainsi qu'à l'édition (PATCH) et la suppression (DELETE, soft-delete) de chaque ressource.",
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
            money: "Montants exposés en centimes (`cents`) + version formatée.",
            writes: "PATCH /<ressource>/:id pour éditer, DELETE /<ressource>/:id pour supprimer (soft-delete). " \
                    "Corps JSON encapsulé sous la clé de la ressource, ex. { \"booking\": { \"status\": \"confirmed\" } }. " \
                    "La création (POST) est exposée sur catalog_items, ses prices, paper_sheets, member_accounts, " \
                    "account_entries et les règlements — les données d'exploitation n'ont pas à passer par un script versionné dans un dépôt public.",
            upsert: "POST est un UPSERT partout où une clé naturelle existe : canal + nom pour un article, " \
                    "mois + canal pour une fiche, nom pour un compte membre, `idempotency_key` pour une écriture, " \
                    "`reference` pour un règlement, `external_ref` pour une note du calendrier. Rejouer un import " \
                    "ne duplique donc rien ; `meta.created` dit si l'enregistrement a été créé ou retrouvé.",
            soft_delete: "DELETE effectue une suppression douce (soft-delete) : l'enregistrement disparaît de l'API mais reste auditable."
          },
          resources: [
            { name: "customers", path: api_v1_customers_path, description: "Clients (particuliers/organisations). Filtres: q, customer_type." },
            { name: "stays", path: api_v1_stays_path, description: "Séjours regroupant les items réservés d'un client. Filtres: customer_id, status." },
            { name: "bookings", path: api_v1_bookings_path, description: "Réservations de séjour (logements). Filtres: from_date, to_date, status, lodging_id." },
            { name: "space_bookings", path: api_v1_space_bookings_path, description: "Réservations de salles/espaces. Filtres: from_date, to_date, status." },
            { name: "availability", path: api_v1_availability_path, description: "Disponibilité par logement/espace sur une plage de dates. Requiert ?from= & ?to=." },
            { name: "lodgings", path: api_v1_lodgings_path, description: "Catalogue des hébergements (prix, chambres, description)." },
            { name: "rooms", path: api_v1_rooms_path, description: "Chambres rattachées aux hébergements." },
            { name: "spaces", path: api_v1_spaces_path, description: "Espaces/salles louables." },
            { name: "humans", path: api_v1_humans_path, description: "Membres du collectif." },
            { name: "cycles", path: api_v1_cycles_path, description: "Cycles de l'organisation (périodes datées)." },
            { name: "cycle_actions", path: api_v1_cycle_actions_path, description: "Actions de cycle par membre. Filtres: human_id, category, completed." },
            { name: "human_roles", path: api_v1_human_roles_path, description: "Rôles datés par membre (ex. gardes / Veilleur·euse). Filtres: human_id, role_id, status (selected|backup), from, to." },
            { name: "tasks", path: api_v1_tasks_path, description: "Tâches de l'organisation. Filtres: status, project_id." },
            { name: "payments", path: api_v1_payments_path, description: "Paiements liés aux réservations (identifiants Stripe non exposés)." },
            { name: "notes", path: api_v1_notes_path, description: "Notes (post-it datés) du calendrier partagé. `color` porte le TYPE de note (yellow=Nettoyages, pink=Activités, green=Locations tente/van, blue=Informations/Autres, orange=Pizza party). Filtres: from, to, color, external_ref, q. POST/PATCH/DELETE exposés ; POST est un upsert sur `external_ref`." },
            { name: "events", path: api_v1_events_path, description: "Événements (agenda du site les4sources.be), brouillons compris. POST = upsert sur `slug` ; `published: true` publie sur le site ; `category` = slug de catégorie ; `image_url` (https) télécharge l'image ; `registration_url` = lien d'inscription. PATCH/DELETE (soft-delete). Filtres: from, to, published, category, slug, q." },
            { name: "event_categories", path: api_v1_event_categories_path, description: "Catégories d'événements avec leur pôle (couleur et picto des cartes du site). POST (upsert sur le slug, dérivé du nom) et PATCH pour poser `pole`, `name`, `color`." },
            { name: "catalog_items", path: api_v1_catalog_items_path, description: "Catalogue bar/cellier/repas. Filtres: channel, q, active, on (date de résolution du prix). POST/PATCH/DELETE exposés." },
            { name: "member_accounts", path: api_v1_member_accounts_path, description: "Comptes courants internes des ménages et personnes, avec leur solde recalculé. POST (upsert sur le nom)/PATCH exposés. Filtres: q, kind, active." },
            { name: "account_entries", path: api_v1_account_entries_path, description: "Écritures de compte courant hors fiche papier (charges, loyers, forfaits, arrondis). POST avec idempotency_key. Filtres: member_account_id, flow, source, from, to." },
            { name: "settlements", path: api_v1_member_account_settlements_path(":member_account_id"), description: "Règlements reçus sur un compte : POST /member_accounts/:id/settlements. Idempotent sur `reference`." },
            { name: "general_accounts", path: api_v1_general_accounts_path, description: "Plan comptable général (PCMN). POST/PATCH, upsert sur le code ; classe et nature déduites du numéro. Filtres: q, klass, nature, active." },
            { name: "analytic_accounts", path: api_v1_analytic_accounts_path, description: "Axes analytiques, rattachables à une équipe. POST/PATCH, upsert sur le code. Filtres: q, team_id." },
            { name: "fiscal_years", path: api_v1_fiscal_years_path, description: "Exercices comptables par entité. POST/PATCH, upsert sur (entité, date de début) ; un exercice clôturé sort en 409. Filtres: legal_entity_id, status." },
            { name: "opening_entries", path: api_v1_opening_entries_path, description: "Écritures d'à-nouveau. La SEULE écriture comptable que l'API pose ; refusée si elle ne balance pas, et rejouée par contre-passation." },
            { name: "cash_accounts", path: api_v1_cash_accounts_path, description: "Comptes de trésorerie (banque, caisse, Stripe) et leur contrepartie générale. POST/PATCH, upsert sur le nom. Filtres: kind, active." },
            { name: "coda_imports", path: api_v1_coda_imports_path, description: "Dépôt d'extraits CODA : POST { filename, content }. Rejouer un fichier déjà déposé rend 200 sans rien créer ; un fichier refusé rend 422 avec le motif chiffré." },
            { name: "cash_entries", path: api_v1_cash_entries_path, description: "Lignes du journal de trésorerie hors CODA (caisse en espèces). POST idempotent sur external_ref ; compte adressable par son nom. Filtres: cash_account_id, status, from, to." },
            { name: "paper_sheets", path: api_v1_paper_sheets_path, description: "Fiches papier mensuelles et leur encodage matriciel (POST /paper_sheets/:id/encode). Filtres: channel, status, period_month." },
            { name: "allocation_rules", path: api_v1_allocation_rules_path, description: "Règles d'affectation du rapprochement assisté. Une règle PROPOSE, elle ne comptabilise jamais ; l'acceptation des suggestions reste au navigateur. POST/PATCH/DELETE exposés ; POST est un upsert sur le libellé. Compte et pôle adressables par `general_account_code` et `team_name`. Filtres: direction, active." },
            { name: "cash_motifs", path: api_v1_cash_motifs_path, description: "Motifs de la feuille de caisse — le motif EST l'affectation (compte, pôle, entité). Une ligne déjà saisie en garde une COPIE : réaffecter un motif ne réécrit jamais le passé. POST/PATCH exposés ; POST est un upsert sur le libellé. Filtres: direction, active." },
            { name: "plant_species", path: api_v1_plant_species_path, description: "Espèces nourricières du domaine, fiche botanique et fenêtres de récolte par défaut. POST (upsert sur le nom)/PATCH. Filtre: q." },
            { name: "plant_varieties", path: api_v1_plant_varieties_path, description: "Variétés d'une espèce. POST (upsert sur espèce + nom). Filtre: plant_species_id." },
            { name: "plants", path: api_v1_plants_path, description: "Plantes nourricières : dossier, numéro décimal, position (latitude/longitude → point sur la carte), fenêtres de récolte (propres ou héritées). POST (upsert sur notion_url)/PATCH/DELETE ; species_name/variety_name résolus ; listes fermées en clé ou libellé Notion. Sous-ressources : /plants/:id/notes (POST), /plants/:id/photos (POST multipart photos[], DELETE). Filtres: status, zone, placed, q, number, plant_species_id." },
            { name: "map_features", path: api_v1_map_features_path, description: "Objets de la carte en GeoJSON (zones, accès, points) dans une couche (layer_id ou layer_kind). POST/PATCH/DELETE ; notes et photos comme pour les plantes. Filtres: layer_id, layer_kind, kind." },
            { name: "map_notes", path: "/api/v1/map_notes/:id", description: "Notes datées d'une plante ou d'un objet de la carte : PATCH/DELETE. Création sous /plants/:id/notes ou /map_features/:id/notes." },
            { name: "map_tasks", path: api_v1_map_tasks_path, description: "Tâches de gestion de la carte sur une plante ou un objet (subject_type MapFeature|Plant, subject_id), par mois. POST/PATCH/DELETE. Filtres: subject_type, subject_id, month." }
          ],
          example: "curl -H 'Authorization: Bearer $AGENT_API_TOKEN' #{api_v1_bookings_url}"
        }
      end
    end
  end
end
