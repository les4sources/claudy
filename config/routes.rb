Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  resources :bookings
  resources :lodgings
  resources :rooms

  namespace :public do
    resources :bookings, only: [:new, :create]
  end

  # Defines the root path route ("/")
  root "bookings#index"
end
