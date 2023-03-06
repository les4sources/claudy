Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  if Rails.env.development?
    mount Lookbook::Engine, at: "/lookbook"
  end

  resources :booking_prices, only: [:create]
  resources :bookings do
    get "past", on: :collection
  end
  resources :event_categories
  resources :events
  resources :lodgings
  resources :notes
  resources :rooms

  get "pages/other_bookings", to: "pages#other_bookings"

  namespace :public do
    resources :bookings, only: [:new, :create]
    get "reservation/:token", to: "bookings#show", as: :booking
    get "calendrier-hebergements", to: "calendars#lodgings"
    get "calendar-lodgings-modal", to: "calendars#lodgings_modal"
  end

  # Defines the root path route ("/")
  root "pages#calendar"
end
