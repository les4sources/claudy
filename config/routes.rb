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
    resources :gathering_actions, only: [:create, :update, :destroy] do
      member do
        patch :toggle_completed
      end
    end
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
    end
  end
  resources :human_roles
  resources :notes
  resources :payments, only: [:index, :show, :destroy]
  resources :products
  resources :projects
  resources :rental_items
  resources :reports
  resources :roles
  resources :rooms
  resources :services
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

  resources :bookings do
    collection do
      get "past"
      get "search"
    end
    resources :payments
  end

  resources :space_bookings do
    get "past", on: :collection
  end

  # Pôle Accueil : clients (Customer) + fusion de doublons / re-ventilation.
  resources :customers, only: [:index, :show, :edit, :update] do
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

  # Détails d'un séjour (chargé dans une modale Turbo Frame depuis la page client).
  resources :stays, only: [:show]
  resources :experience_bookings, only: [:index, :update]

  # Espace client activités (token-based, sans Devise).
  get  "mon-sejour/:token/activites", to: "public/activity_selections#show",   as: :public_activity_selection
  post "mon-sejour/:token/activites", to: "public/activity_selections#create",  as: :public_activity_selection_create

  get "comptabilite", to: "accounting#index", as: :accounting

  get "pages/day", to: "pages#day", as: :day_details
  get "pages/dashboard", to: "pages#dashboard", as: :dashboard
  get "pages/other_bookings", to: "pages#other_bookings"
  get "pages/other_space_bookings", to: "pages#other_space_bookings"
  get "pages/month_details", to: "pages#month_details", as: :month_details

  get "reports/lodging/:id", to: "reports#lodging", as: :lodging_reports

  # Funnel B2C natif /reservation — 3 étapes (tranche 2).
  # Étape 1 : dates + groupe + animal  →  Étape 2 : composition  →  Étape 3 : coordonnées
  get  "reservation",              to: "public/reservations#start",              as: :public_reservation_start
  get  "reservation/sejour",       to: "public/reservations#dates",              as: :public_reservation_dates
  post "reservation/sejour",       to: "public/reservations#advance_dates",      as: :public_reservation_advance_dates
  get  "reservation/composer",     to: "public/reservations#compose",            as: :public_reservation_compose
  post "reservation/devis",        to: "public/reservations#quote",              as: :public_reservation_quote
  post "reservation/composer",     to: "public/reservations#advance_contact",    as: :public_reservation_advance_contact
  get  "reservation/activites",    to: "public/reservations#activities",         as: :public_reservation_activities
  get  "reservation/coordonnees",  to: "public/reservations#contact",            as: :public_reservation_contact
  post "reservation/coordonnees",  to: "public/reservations#create",             as: :public_reservation_create
  get  "reservation/calendrier",   to: "public/reservations#availability_calendar", as: :public_reservation_availability_calendar

  # Vue admin Pôle Accueil — index des Stays récents filtrable par source (Devise).
  get "sejours/recents", to: "stays#recent", as: :recent_stays

  namespace :public do
    resources :bookings, only: [:new, :create] do
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
      resources :tasks, only: [:index, :show, :update, :destroy]
      resources :payments, only: [:index, :show, :update, :destroy]
    end
  end

  # Defines the root path route ("/")
  root "pages#calendar"
end
