# Contrôle des rôles d'accès (Michael, 2026-10-09), cf. `Access`.
#
# Chaque contrôleur déclare la section qu'il sert :
#
#   access_section :events
#   access_section :calendar, only: %i[calendar day]
#
# Sans déclaration, la section est `:full` : réservée aux Sourciers. Un rôle
# en lecture seule n'a que les requêtes GET ; toute écriture lui est refusée.
#
# Un compte « Restreint à ses activités » (porteur externe) n'est pas concerné :
# sa propre liste blanche (`BaseController::RESTRICTED_ALLOWLIST`) est plus
# étroite que n'importe quel rôle et passe avant.
module AccessControl
  extend ActiveSupport::Concern

  NO_ACCESS = "Vous n'avez pas accès à cette section.".freeze
  READ_ONLY = "Lecture seule : vous ne pouvez rien modifier ici.".freeze

  included do
    class_attribute :access_sections, instance_writer: false, default: {}
    before_action :authorize_access!
    helper_method :access_home_path
  end

  class_methods do
    def access_section(section, only: nil)
      keys = only ? Array(only).map(&:to_s) : ["*"]
      self.access_sections = access_sections.merge(keys.index_with { section.to_sym })
    end
  end

  private

  def current_access_section
    access_sections[action_name] || access_sections["*"] || :full
  end

  # Mêmes questions côté vues : `AccessHelper`.
  def section_readable?(section) = current_user&.can_read?(section) || false

  def section_writable?(section) = current_user&.can_write?(section) || false

  def authorize_access!
    return if current_user.nil? || current_user.restricted_to_experiences?

    level = current_user.access_level(current_access_section)
    return if level == :write
    return if level == :read && (request.get? || request.head?)

    deny_access!(level == :read ? READ_ONLY : NO_ACCESS)
  end

  # La première page que le compte a le droit d'ouvrir : là où on le renvoie
  # quand il frappe à une porte fermée. `nil` pour un compte sans aucun rôle.
  def access_home_path
    return root_path if section_readable?(:calendar)
    return experiences_path if section_readable?(:events)
    return finance_accounts_path if section_readable?(:accounts)
    return finance_accounting_path if section_readable?(:accounting)
    return map_path if section_readable?(:map)
    return dashboard_path if section_readable?(:everyone)

    nil
  end

  def deny_access!(message)
    home = access_home_path

    if home.nil?
      render "access/none", layout: "devise", status: :forbidden, formats: :html
    elsif !request.format.html? && !request.format.turbo_stream?
      head :forbidden
    elsif turbo_frame_request?
      render plain: message, status: :forbidden
    elsif request.get? || request.head?
      redirect_to home, alert: message
    else
      redirect_back fallback_location: home, alert: message, status: :see_other
    end
  end
end
