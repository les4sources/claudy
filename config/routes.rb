Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  if Rails.env.development?
    mount Lookbook::Engine, at: "/lookbook"
  end

  resources :booking_prices, only: [:create]
  resources :bundles
  resources :event_categories
  resources :events
  resources :gathering_categories
  resources :gatherings do
    collection do
      post :quick_create
    end
    member do
      patch :update_report
    end
    resources :agenda_items, except: [:index, :show] do
      member do
        patch :toggle_completed
        patch :move
      end
      collection do
        patch :reorder
      end
    end
    resources :gathering_actions, only: [:create, :show, :edit, :update, :destroy] do
      member do
        patch :toggle_completed
      end
    end
  end
  # Coworking (epic #126, Phase 1) — domaine indépendant des séjours : packs de
  # journées achetés par un client, journées posées dans la limite des crédits.
  resources :coworking_packs, only: [:index, :show, :new, :create, :destroy] do
    resources :coworking_reservations, only: [:create, :destroy]
  end
  resources :decisions
  get "organisation/decisions", to: "decisions#index", as: :organisation_decisions
  resources :experiences do
    resources :experience_availabilities, only: [:create, :destroy], path: :disponibilites
  end
  resources :lodgings
  resources :humans do
    member do
      patch :toggle_cycle_active
      post :create_account
      post :resend_invitation
    end
  end
  resources :human_roles
  resources :notes
  resources :payments, only: [:index, :show, :destroy]
  resources :products
  resources :projects
  resources :rates, only: [:index, :update]
  resources :rental_items
  resources :reports
  resources :roles
  resources :rooms
  resources :services
  resources :spaces
  resources :tasks
  resources :teams
  resources :watchman_notes

  # Organisation
  get "organisation", to: "organisation#index", as: :organisation
  resources :cycles
  resources :cycle_actions, except: [:show] do
    member do
      patch :toggle_completed
      patch :defer
      patch :archive
      patch :unarchive
    end
    collection do
      patch :reorder
      patch :archive_completed
    end
  end
  get "organisation/member/:human_id", to: "organisation#member", as: :organisation_member
  get "organisation/member/:human_id/archives", to: "organisation#archives", as: :organisation_member_archives

  # Épic #81 / issue #99 — le séjour (`resources :stays`) est le SEUL point
  # d'entrée de création ET d'édition. `bookings`/`space_bookings` ne gardent que
  # les routes d'occupation : index/show/past/search/destroy + `edit` (pure
  # redirection vers le séjour). `new`/`create` retirés (Phase 9), `update` retiré
  # (issue #99 — l'écran d'édition legacy n'existe plus, rien ne peut soumettre).
  resources :bookings, except: [:new, :create, :update] do
    collection do
      get "past"
      get "search"
    end
    resources :payments
  end

  resources :space_bookings, except: [:new, :create, :update] do
    get "past", on: :collection
  end

  # Pôle Accueil : clients (Customer) + fusion de doublons / re-ventilation.
  resources :customers, only: [:index, :show, :edit, :update, :destroy] do
    collection do
      get "search" # autocomplete JSON pour la re-ventilation
    end
    member do
      get "merge"
      get "merge_preview"
      post "merge_commit"
      post "reassign"
    end
  end

  # Vue admin Pôle Accueil — index des Stays récents filtrable par source (Devise).
  # URLs admin en anglais. Déclarée AVANT `resources :stays` pour que
  # /stays/recents ne soit pas capté par la route /stays/:id.
  get "stays/recents", to: "stays#recent", as: :recent_stays

  # Détails d'un séjour (chargé dans une modale Turbo Frame depuis la page client).
  # Le CRUD admin d'une activité SUR un séjour (epic #55, Phase 6) est imbriqué
  # sous cette ressource : la création porte TOUJOURS le séjour dans l'URL, si
  # bien qu'une activité ne peut jamais naître sans son séjour d'attache.
  # CRUD Séjour admin (epic #66, Phase 1) — le séjour devient le point d'entrée
  # de création composable côté admin (hébergement + activités). URLs anglaises.
  # `show` reste rendu sans layout (fragment de modale) ; new/edit sont des pages
  # pleines. La route `stays/recents` ci-dessus est déclarée AVANT pour ne pas
  # être captée par `/stays/:id`.
  resources :stays, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    collection do
      # Vérification de disponibilité en temps réel dans le form de composition
      # (issue #77) : lodging_id + dates → JSON { available: bool }. Informe sans
      # bloquer (le forçage reste la seule décision de blocage).
      get :availability
      # Grilles de composition datées (espaces + camping/van) rechargées quand
      # les dates du séjour changent : rend le frame `stay_compose_grids`.
      get :compose_grids
      # Devis live du form de composition (issue #73) : recalcule le panneau
      # « Devis (B2C) » en Turbo Stream à chaque changement, via PricingModel.
      post :quote
      # Fusion de séjours depuis le calendrier (epic #81, Phase 2). Trois étapes
      # rendues PAR LE SERVEUR (fragments HTML, aucune vérité recalculée en JS) :
      #   - merge_setup   : étape A — désignation du séjour survivant (cartes radio) ;
      #   - merge_preview : étape B — aperçu dry-run (Stays::MergePreview) ;
      #   - merge         : commit — Stays::MergeService, puis redirection + flash.
      post :merge_setup
      post :merge_preview
      post :merge
    end
    member do
      # Action rapide depuis la modale du calendrier (issue #76) : bascule
      # pending ↔ confirmed sans ouvrir le form d'édition, réponse Turbo Stream.
      patch :update_status
      # Demande de modification client (issue #133) : approbation / refus par
      # l'équipe. C'est le seul chemin qui applique la demande au séjour.
      post :approve_change_request
      post :refuse_change_request
    end
    resources :experience_bookings, only: [:create]
  end
  resources :experience_bookings, only: [:index, :update, :destroy] do
    member do
      patch :confirm         # validation par le porteur (canal admin)
      get   :new_refusal     # formulaire de refus (raison obligatoire)
      patch :refuse          # application du refus avec raison
    end
  end

  # Canal jeton — validation d'activité par le porteur depuis l'email (epic #55,
  # Phase 2). La VALIDATION passe par une page de confirmation légère (GET) puis
  # un POST : jamais de mutation sur simple GET préchargeable. Le REFUS exige une
  # raison, donc une connexion : le lien renvoie vers le formulaire admin.
  get  "activites/valider/:token",  to: "experience_booking_validations#show",    as: :activity_validation
  post "activites/valider/:token",  to: "experience_booking_validations#confirm", as: :activity_validation_confirm
  get  "activites/refuser/:token",  to: "experience_booking_validations#refuse",  as: :activity_validation_refuse

  # Espace client activités (token-based, sans Devise).
  get  "mon-sejour/:token/activites", to: "public/activity_selections#show",   as: :public_activity_selection
  post "mon-sejour/:token/activites", to: "public/activity_selections#create",  as: :public_activity_selection_create

  get "comptabilite", to: "accounting#index", as: :accounting

  get "pages/day", to: "pages#day", as: :day_details
  get "recent-activity", to: "pages#recent_activity", as: :recent_activity
  get "pages/dashboard", to: "pages#dashboard", as: :dashboard
  get "pages/other_bookings", to: "pages#other_bookings"
  get "pages/other_space_bookings", to: "pages#other_space_bookings"
  get "pages/month_details", to: "pages#month_details", as: :month_details

  get "reports/lodging/:id", to: "reports#lodging", as: :lodging_reports

  # Funnel B2C natif /reservation — 4 étapes (tranche 2 + epic #55 Phase 4).
  # Étape 1 : dates + groupe + animal  →  Étape 2 : composition  →  Étape 3 :
  # activités  →  Étape 4 : coordonnées
  get  "reservation",              to: "public/reservations#start",              as: :public_reservation_start
  get  "reservation/sejour",       to: "public/reservations#dates",              as: :public_reservation_dates
  post "reservation/sejour",       to: "public/reservations#advance_dates",      as: :public_reservation_advance_dates
  get  "reservation/composer",     to: "public/reservations#compose",            as: :public_reservation_compose
  post "reservation/devis",        to: "public/reservations#quote",              as: :public_reservation_quote
  post "reservation/composer",     to: "public/reservations#advance_compose",    as: :public_reservation_advance_compose
  get  "reservation/activites",    to: "public/reservations#activities",         as: :public_reservation_activities
  post "reservation/activites",    to: "public/reservations#advance_activities", as: :public_reservation_advance_activities
  get  "reservation/coordonnees",  to: "public/reservations#contact",            as: :public_reservation_contact
  post "reservation/coordonnees",  to: "public/reservations#create",             as: :public_reservation_create
  get  "reservation/calendrier",   to: "public/reservations#availability_calendar", as: :public_reservation_availability_calendar

  # Page client du séjour-composite (epic #26, Phase 1) — jeton, sans Devise.
  # Route à la racine (et non sous /public) : c'est l'URL envoyée aux clients et
  # la cible des redirections Stripe, on la garde courte, comme /reservation/sejour.
  # Portail client (epic #126, Phase 2) — connexion par code à usage unique
  # envoyé par email. Session propre (cookie signé dédié), aucun lien avec
  # Devise : le portail n'ouvre JAMAIS d'accès admin.
  get    "portail",              to: "portal/sessions#new",         as: :portal
  post   "portail/code",         to: "portal/sessions#create_code",  as: :portal_code
  post   "portail/connexion",    to: "portal/sessions#create",       as: :portal_login
  delete "portail/deconnexion",  to: "portal/sessions#destroy",      as: :portal_logout
  get    "portail/sejours",      to: "portal/stays#index",           as: :portal_stays

  get "sejour/:token", to: "public/stays#show", as: :public_stay

  # Paiement du solde exigible du séjour (epic #55, Phase 3) — POST scellé par le
  # même jeton que la page client ; crée/rafraîchit le paiement puis part sur
  # Stripe Checkout.
  post "sejour/:token/payer-le-solde", to: "public/stay_balance_payments#create", as: :public_stay_balance_payment

  # Demande de modification de séjour par le client (issue #133) — canal jeton.
  # C'est une DEMANDE : rien n'est appliqué avant validation par l'équipe.
  get  "sejour/:token/modification",       to: "public/stay_change_requests#new",    as: :new_public_stay_change_request
  post "sejour/:token/modification/devis", to: "public/stay_change_requests#quote",  as: :public_stay_change_request_quote
  post "sejour/:token/modification",       to: "public/stay_change_requests#create", as: :public_stay_change_requests

  namespace :public do
    # Épic #81, Phase 9 — demande de réservation publique legacy retirée
    # (new/create). Le funnel natif /reservation est le seul point d'entrée public.
    # On conserve `edit_estimated_arrival`/`update_estimated_arrival` (services aux
    # clients existants) : ce sont des routes membres qui n'ont pas besoin de
    # new/create.
    resources :bookings, only: [] do
      get "edit_estimated_arrival", on: :member
      patch "update_estimated_arrival", on: :member
    end
    resources :payments, param: :uuid do
      member do
        get "pay"
      end
    end
    get "reservation/:token", to: "bookings#show", as: :booking
    get "espaces/:token", to: "space_bookings#show", as: :space_booking
    get "calendrier-hebergements", to: "calendars#lodgings"
    get "calendar-lodgings-modal", to: "calendars#lodgings_modal"
  end

  namespace :webhooks do
    resource :stripe_hooks, only: :create
  end

  # Private read-only API for AI agents. Authenticated by a static bearer token
  # (ENV["AGENT_API_TOKEN"]). Self-documented: GET /api/v1 lists resources and
  # GET /api/v1/openapi serves the OpenAPI 3 spec.
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get "/", to: "index#show"
      get "openapi", to: "openapi#show"
      get "availability", to: "availability#index"

      # Reads (index/show) plus edit (PATCH/PUT update) and delete (soft-delete).
      # Create (POST) is intentionally not exposed.
      resources :customers, only: [:index, :show, :update, :destroy]
      resources :stays, only: [:index, :show, :update, :destroy]
      resources :bookings, only: [:index, :show, :update, :destroy]
      resources :space_bookings, only: [:index, :show, :update, :destroy]
      resources :lodgings, only: [:index, :show, :update, :destroy]
      resources :rooms, only: [:index, :show, :update, :destroy]
      resources :spaces, only: [:index, :show, :update, :destroy]
      resources :humans, only: [:index, :show, :update, :destroy]
      resources :cycles, only: [:index, :show, :update, :destroy]
      resources :cycle_actions, only: [:index, :show, :update, :destroy]
      resources :human_roles, only: [:index, :show]
      resources :tasks, only: [:index, :show, :update, :destroy]
      resources :payments, only: [:index, :show, :update, :destroy]
    end
  end

  # Defines the root path route ("/")
  root "pages#calendar"
end
