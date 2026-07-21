module Portal
  # Connexion au portail par code à usage unique envoyé par email (pas de mot
  # de passe, pas de Devise).
  #
  # Anti-énumération : quel que soit l'email saisi — inconnu, fourre-tout, ou
  # bien réel — la réponse est TOUJOURS la même. Rien dans le corps, le statut
  # ou le temps de réponse ne dit si un compte existe.
  class SessionsController < Portal::BaseController
    def new
      redirect_to portal_stays_path and return if portal_signed_in?

      @email = params[:email].to_s
    end

    # POST /portail/code — émet et envoie un code, si et seulement si l'email
    # correspond à un client réel non fourre-tout.
    def create_code
      email = params[:email].to_s.strip.downcase

      if deliverable_customer(email)
        otp, code = PortalOtp.issue!(email)
        PortalMailer.login_code(email: email, code: code, expires_at: otp.expires_at).deliver_later
      end

      @email = email
      render :verify
    end

    # POST /portail/connexion — vérifie le code saisi.
    def create
      email = params[:email].to_s.strip.downcase
      customer = deliverable_customer(email)

      if customer && PortalOtp.verify(email, params[:code])
        sign_in_portal(customer)
        redirect_to portal_stays_path
      else
        @email = email
        flash.now[:alert] = t("portal.session.invalid_code")
        render :verify, status: :unprocessable_entity
      end
    end

    def destroy
      sign_out_portal
      redirect_to portal_path, notice: t("portal.session.signed_out")
    end

    private

    # Le client à qui l'on accepte d'envoyer un code : email exact, et JAMAIS un
    # fourre-tout (`Customer#catch_all?`) — ces adresses partagées donneraient
    # accès aux séjours de dizaines de clients.
    def deliverable_customer(email)
      return nil if email.blank?

      customer = Customer.find_by(email: email)
      return nil if customer.nil? || customer.catch_all?

      customer
    end
  end
end
