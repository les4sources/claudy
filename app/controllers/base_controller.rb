class BaseController < ActionController::Base
  layout "application"

  before_action :authenticate

  def authenticate
    authenticate_or_request_with_http_basic do |username, password|
      username == ENV.fetch('AUTH_USERNAME') && password == ENV.fetch('AUTH_PASSWORD')
    end if Rails.env.production?
  end

  def render *args
    set_presenters
    super
  end

  private

  def set_error_flash(object, error_message)
    if object.valid?
      flash.now[:error] = error_message
    else
      flash.now[:error] = object.errors.messages.values.flatten.join("<br>")
    end
  end
end
