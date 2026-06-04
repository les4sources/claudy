class BaseController < ActionController::Base
  include PublicActivity::StoreController
  
  layout "application"

  before_action :authenticate_user!
  before_action :set_paper_trail_whodunnit

  helper_method :current_human

  # breadcrumb "Calendrier", :root_path

  def render *args
    set_presenters
    super
  end

  private

  # Identifie l'humain (porteur d'activité, membre de l'équipe…) lié à
  # l'utilisateur connecté. Centralisé ici pour rester cohérent partout —
  # cf. epic #25 Phase 2 (comptes porteurs).
  def current_human
    current_user&.human || Human.where(status: "active").first
  end

  def set_error_flash(object, error_message)
    if object.valid?
      flash.now[:error] = error_message
    else
      flash.now[:error] = object.errors.messages.values.flatten.join("<br>")
    end
  end
end
