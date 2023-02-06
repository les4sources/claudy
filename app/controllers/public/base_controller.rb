class Public::BaseController < ActionController::Base
  layout "public"

  # default_form_builder TailwindFormBuilder

  private

  def set_error_flash(object, error_message)
    if object.valid?
      flash.now[:error] = error_message
    else
      flash.now[:error] = object.errors.messages.values.flatten.join("<br>")
    end
  end
end
