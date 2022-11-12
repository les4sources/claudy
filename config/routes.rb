Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  resources :bookings
  resources :lodgings
  resources :rooms

  namespace :public do
    resources :bookings, only: [:new, :create, :show]
    get "calendrier-hebergements", to: "calendars#lodgings"
  end

  # Defines the root path route ("/")
  root "pages#calendar"
end
