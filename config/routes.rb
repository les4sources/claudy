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
  resources :experiences
  resources :lodgings
  resources :humans
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
  resources :stays do
    resources :stay_items
    resources :payments
    collection do 
      get "past"
    end
    member do
      post "save_dates" 
    end
  end
  resources :tasks
  resources :teams

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

  get "comptabilite", to: "accounting#index", as: :accounting

  get "stay_prices/calculate_item_price", to: "stay_prices#calculate_item_price", as: :calculate_item_price

  get "pages/day", to: "pages#day", as: :day_details
  get "pages/dashboard", to: "pages#dashboard", as: :dashboard
  get "pages/other_bookings", to: "pages#other_bookings"
  get "pages/other_space_bookings", to: "pages#other_space_bookings"
  get "pages/other_stays", to: "pages#other_stays"

  get "reports/lodging/:id", to: "reports#lodging", as: :lodging_reports

  get 'customers/lookup', to: 'customers#lookup'

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

  # Defines the root path route ("/")
  root "pages#calendar"
end
