class Public::BaseController < ActionController::Base
  layout "public"

  # Langues des pages client à jeton (issue #15). Le lien envoyé au client pointe
  # toujours vers le FR ; `?locale=xx` bascule, et le choix est mémorisé en
  # session pour les navigations suivantes. Toute valeur hors whitelist retombe
  # sur le FR — jamais d'exception, jamais de 500.
  PUBLIC_LOCALES = %w[fr nl en].freeze

  # default_form_builder TailwindFormBuilder

  around_action :switch_locale

  rescue_from ActionController::RoutingError, with: :render_404

  private

  def switch_locale(&action)
    locale = requested_locale
    session[:public_locale] = locale
    I18n.with_locale(locale, &action)
  end

  def requested_locale
    candidate = params[:locale].presence || session[:public_locale]
    PUBLIC_LOCALES.include?(candidate.to_s) ? candidate.to_s : I18n.default_locale.to_s
  end

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
