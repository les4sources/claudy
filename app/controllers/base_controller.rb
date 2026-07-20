class BaseController < ActionController::Base
  include PublicActivity::StoreController
  
  layout "application"

  before_action :authenticate_user!
  before_action :enforce_active_member
  before_action :restrict_experience_carriers
  before_action :set_paper_trail_whodunnit

  helper_method :current_human

  # Contrôleurs/actions accessibles à un utilisateur « restreint à ses
  # activités » (porteur cloisonné). Tout le reste de l'app le renvoie vers son
  # planning d'activités. La déconnexion (Devise::SessionsController) n'hérite
  # PAS de BaseController, elle reste donc toujours disponible.
  RESTRICTED_ALLOWLIST = {
    "experiences" => %w[index show],
    "experience_availabilities" => %w[create destroy],
    "experience_bookings" => %w[index update confirm new_refusal refuse]
  }.freeze

  # breadcrumb "Calendrier", :root_path

  def render *args
    set_presenters
    super
  end

  private

  # Coupe la session d'un compte dont le membre d'équipe a été désactivé — même
  # si la session était déjà ouverte avant la désactivation. Le refus au moment
  # du sign-in est géré par `User#active_for_authentication?`.
  def enforce_active_member
    return unless current_user&.member_deactivated?

    sign_out(current_user)
    redirect_to new_user_session_path,
                alert: I18n.t("devise.failure.account_deactivated")
  end

  # Cloisonne un utilisateur « restreint » sur son planning d'activités : toute
  # page hors allowlist le renvoie vers la liste de SES activités.
  def restrict_experience_carriers
    return unless current_user&.restricted_to_experiences?

    allowed = RESTRICTED_ALLOWLIST[controller_name]&.include?(action_name)
    return if allowed

    redirect_to experiences_path
  end

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
