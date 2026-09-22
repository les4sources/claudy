module Portal
  # Connexion au portail par code à usage unique envoyé par email (pas de mot
  # de passe, pas de Devise).
  #
  # Deux contextes, un seul mécanisme OTP :
  #
  #   * « stays » (défaut) — accès à « Mes séjours ». Anti-énumération STRICTE :
  #     un code n'est émis QUE pour un client réel non fourre-tout ; la réponse
  #     reste identique quel que soit l'email (connu, inconnu, fourre-tout).
  #
  #   * « coworking » — achat/réservation de coworking. Un prospect sans compte
  #     doit pouvoir acheter : on émet donc pour TOUTE adresse valide non
  #     fourre-tout, et le `Customer` (individual) est créé à la connexion.
  #     Aucune fuite : le comportement est identique pour toute adresse valide.
  #
  #   * « consignor » — espace artisan en dépôt-vente (epic #359, phase 1).
  #     Anti-énumération STRICTE comme « stays » : un code n'est émis que pour un
  #     artisan actif dont l'administration a ouvert l'espace. Rien n'est jamais
  #     créé ici — un artisan existe parce qu'un contrat existe.
  class SessionsController < Portal::BaseController
    CONTEXTS = %w[stays coworking consignor].freeze

    def new
      @context = sanitized_context(params[:context])
      redirect_to portal_consignments_path and return if portal_consignor_signed_in?
      redirect_to portal_stays_path and return if portal_signed_in?

      @email = params[:email].to_s
    end

    # POST /portail/code — émet et envoie un code sous les conditions du contexte
    # (client réel pour « stays », email valide pour « coworking ») et le
    # rate-limit (PortalOtp.throttled?). PRG : on redirige TOUJOURS vers la page
    # de saisie, quelle que soit l'issue.
    def create_code
      email = params[:email].to_s.strip.downcase
      context = sanitized_context(params[:context])

      if otp_eligible?(email, context) && !PortalOtp.throttled?(email)
        otp, code = PortalOtp.issue!(email)
        PortalMailer.login_code(email: email, code: code, expires_at: otp.expires_at).deliver_later
      end

      session[:portal_pending_email] = email
      session[:portal_otp_context] = context
      redirect_to portal_verify_path
    end

    # GET /portail/verification — saisie du code. L'email et le contexte vivent
    # en session, jamais dans l'URL.
    def verify
      @email = session[:portal_pending_email].to_s
      @context = sanitized_context(session[:portal_otp_context])
      redirect_to portal_path if @email.blank?
    end

    # POST /portail/connexion — vérifie le code saisi.
    def create
      email = params[:email].to_s.strip.downcase
      context = sanitized_context(session[:portal_otp_context])

      if context == "consignor"
        return sign_in_consignor(email, params[:code], context)
      end

      if PortalOtp.verify(email, params[:code]) && (customer = customer_for(email, context))
        sign_in_portal(customer)
        session.delete(:portal_otp_context)
        redirect_to(context == "coworking" ? portal_coworking_path : portal_stays_path)
      else
        @email = email
        @context = context
        flash.now[:alert] = t("portal.session.invalid_code")
        render :verify, status: :unprocessable_entity
      end
    end

    def destroy
      sign_out_portal
      redirect_to portal_path, notice: t("portal.session.signed_out")
    end

    private

    def sanitized_context(value)
      CONTEXTS.include?(value.to_s) ? value.to_s : "stays"
    end

    # La porte de l'artisan : même mécanique OTP, autre cookie, autre
    # destination. Un code valide dont l'email n'est plus celui d'un artisan
    # ouvert échoue comme un code faux — on ne dit jamais pourquoi.
    def sign_in_consignor(email, code, context)
      consignor = PortalOtp.verify(email, code) ? Consignor.for_portal_email(email) : nil

      if consignor
        sign_in_portal_consignor(consignor)
        session.delete(:portal_otp_context)
        return redirect_to(portal_consignments_path)
      end

      @email = email
      @context = context
      flash.now[:alert] = t("portal.session.invalid_code")
      render :verify, status: :unprocessable_entity
    end

    # Peut-on émettre un code ? En « stays », uniquement pour un client réel.
    # En « consignor », uniquement pour un artisan dont l'espace est ouvert.
    # En « coworking », pour toute adresse valide non fourre-tout (le compte sera
    # créé à la connexion).
    def otp_eligible?(email, context)
      return deliverable_customer(email).present? if context == "stays"
      return Consignor.for_portal_email(email).present? if context == "consignor"

      Customer.exploitable_email?(email) && !catch_all_email?(email)
    end

    # Le client à connecter après vérification du code. En « stays », il doit
    # exister. En « coworking », on le crée s'il manque (individual).
    def customer_for(email, context)
      return deliverable_customer(email) if context == "stays"
      return nil unless Customer.exploitable_email?(email) && !catch_all_email?(email)

      Customer.find_by(email: email) ||
        Customer.create!(email: email, customer_type: "individual")
    end

    # Le client à qui l'on accepte d'envoyer un code : email exact, et JAMAIS un
    # fourre-tout (`Customer#catch_all?`) — ces adresses partagées donneraient
    # accès aux séjours de dizaines de clients.
    def deliverable_customer(email)
      return nil if email.blank?

      customer = Customer.find_by(email: email)
      return nil if customer.nil? || customer.catch_all?

      customer
    end

    def catch_all_email?(email)
      Customer::CATCH_ALL_EMAILS.include?(email)
    end
  end
end
