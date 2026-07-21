module Portal
  # Socle du portail client (epic #126, Phase 2).
  #
  # La session portail est un cookie SIGNÉ dédié, totalement indépendant de
  # Devise : elle n'ouvre AUCUN accès admin, et l'admin connectée n'ouvre aucun
  # accès portail. Durée 24 h.
  class BaseController < Public::BaseController
    # Layout dédié « sous-bois » du portail (identité distincte du flux public
    # de réservation, cf. app/frontend/stylesheets/portal.css).
    layout "portal"

    SESSION_COOKIE = :portal_customer_id
    SESSION_DURATION = 24.hours

    helper_method :current_portal_customer, :portal_signed_in?

    private

    def current_portal_customer
      return @current_portal_customer if defined?(@current_portal_customer)

      id = cookies.signed[SESSION_COOKIE]
      @current_portal_customer = id.present? ? Customer.find_by(id: id) : nil
    end

    def portal_signed_in? = current_portal_customer.present?

    def sign_in_portal(customer)
      cookies.signed[SESSION_COOKIE] = {
        value: customer.id,
        expires: SESSION_DURATION.from_now,
        httponly: true,
        same_site: :lax
      }
      @current_portal_customer = customer
    end

    def sign_out_portal
      cookies.delete(SESSION_COOKIE)
      @current_portal_customer = nil
    end

    def require_portal_customer
      return if portal_signed_in?

      redirect_to portal_path, alert: t("portal.session.required")
    end
  end
end
