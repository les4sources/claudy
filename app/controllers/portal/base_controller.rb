module Portal
  # Socle du portail client (epic #126, Phase 2).
  #
  # La session portail est un cookie SIGNÉ dédié, totalement indépendant de
  # Devise : elle n'ouvre AUCUN accès admin, et l'admin connectée n'ouvre aucun
  # accès portail. Durée 24 h.
  #
  # DEUX portes, DEUX cookies (epic #359, phase 1, décision 8) : un client
  # (« Mes séjours », coworking) et un artisan en dépôt-vente. Un artisan n'est
  # pas un client des 4 Sources — lui ouvrir la session client lui donnerait les
  # séjours de quelqu'un. Se connecter d'un côté FERME donc l'autre : une seule
  # identité à la fois, et les cloisons tiennent sans dépendre des vues.
  class BaseController < Public::BaseController
    # Layout dédié « sous-bois » du portail (identité distincte du flux public
    # de réservation, cf. app/frontend/stylesheets/portal.css).
    layout "portal"

    SESSION_COOKIE = :portal_customer_id
    PARTNER_COOKIE = :portal_partner_email
    # L'ancien cookie de l'espace artisan (l'id de la fiche) : encore lu, le
    # temps que les sessions ouvertes avant l'espace des partenaires expirent.
    CONSIGNOR_COOKIE = :portal_consignor_id
    SESSION_DURATION = 24.hours

    helper_method :current_portal_customer, :portal_signed_in?,
                  :current_portal_partner, :portal_partner_signed_in?,
                  :current_portal_consignor, :portal_consignor_signed_in?

    private

    def current_portal_customer
      return @current_portal_customer if defined?(@current_portal_customer)

      id = cookies.signed[SESSION_COOKIE]
      @current_portal_customer = id.present? ? Customer.find_by(id: id) : nil
    end

    def portal_signed_in? = current_portal_customer.present?

    def current_portal_partner
      return @current_portal_partner if defined?(@current_portal_partner)

      email = cookies.signed[PARTNER_COOKIE].presence || legacy_consignor_email
      @current_portal_partner = email.present? ? Portal::Partner.for_email(email) : nil
    end

    def portal_partner_signed_in? = current_portal_partner.present?

    def current_portal_consignor = current_portal_partner&.consignor
    def portal_consignor_signed_in? = current_portal_consignor.present?

    def legacy_consignor_email
      id = cookies.signed[CONSIGNOR_COOKIE]
      id.present? ? Consignor.actives.with_portal.find_by(id: id)&.email : nil
    end

    def sign_in_portal(customer)
      write_portal_cookie(SESSION_COOKIE, customer.id)
      forget_partner
      @current_portal_customer = customer
    end

    def sign_in_portal_partner(partner)
      write_portal_cookie(PARTNER_COOKIE, partner.email)
      cookies.delete(CONSIGNOR_COOKIE)
      cookies.delete(SESSION_COOKIE)
      @current_portal_customer = nil
      @current_portal_partner = partner
    end

    def sign_out_portal
      cookies.delete(SESSION_COOKIE)
      forget_partner
      @current_portal_customer = nil
    end

    def forget_partner
      cookies.delete(PARTNER_COOKIE)
      cookies.delete(CONSIGNOR_COOKIE)
      @current_portal_partner = nil
    end

    def require_portal_customer
      return if portal_signed_in?

      redirect_to portal_path, alert: t("portal.session.required")
    end

    def require_portal_consignor
      return if portal_consignor_signed_in?

      redirect_to portal_path(context: "consignor"), alert: t("portal.session.consignor_required")
    end

    def write_portal_cookie(name, value)
      cookies.signed[name] = {
        value: value,
        expires: SESSION_DURATION.from_now,
        httponly: true,
        same_site: :lax
      }
    end
  end
end
