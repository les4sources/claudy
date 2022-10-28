class ApplicationController < ActionController::Base
  http_basic_authenticate_with name: Rails.application.credentials[:claudy][:http_authentication][:username],
                               password: Rails.application.credentials[:claudy][:http_authentication][:password]

  def render *args
    set_presenters
    super
  rescue
    super
  end
end
