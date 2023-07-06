class Public::BaseController < ActionController::Base
  layout "public"

  # default_form_builder TailwindFormBuilder

  rescue_from ActionController::RoutingError, with: :render_404

  private

  def render_404
    render file: "#{Rails.root}/public/404.html", status: 404
  end

  def set_error_flash(object, error_message)
    if object.valid?
      flash.now[:error] = error_message
    else
      flash.now[:error] = object.errors.messages.values.flatten.join("<br>")
    end
  end
end
