class ApplicationController < ActionController::Base
  before_action :authenticate
  # http_basic_authenticate_with name: Rails.application.credentials[:claudy][:http_authentication][:username],
  #                              password: Rails.application.credentials[:claudy][:http_authentication][:password]

  def authenticate
    authenticate_or_request_with_http_basic do |username, password|
      username == Rails.application.credentials[:claudy][:http_authentication][:username] && password == Rails.application.credentials[:claudy][:http_authentication][:password]
    end if Rails.env.production?
  end

  def render *args
    set_presenters
    super
  rescue
    super
  end
end
