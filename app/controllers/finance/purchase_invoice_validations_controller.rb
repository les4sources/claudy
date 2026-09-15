module Finance
  # Canal JETON de validation d'une facture d'achat (epic #240, phase 3),
  # calqué sur `Kitchen::ValidationsController`.
  #
  # Les mêmes choix de sécurité qu'ailleurs :
  #   * VALIDER = mutation bénigne. On ne mute JAMAIS sur un GET, qu'un antivirus
  #     ou un proxy mail peut précharger. Le lien mène à une page de confirmation
  #     dont le bouton POSTe (protégé par CSRF).
  #   * REFUSER = exige un motif, donc une trace nominative, donc un compte. Le
  #     lien force la connexion, puis renvoie vers le formulaire de motif du
  #     canal admin.
  #
  # Hors du namespace `finance` habituel : ce contrôleur ne demande pas de
  # connexion, il n'hérite donc pas de `Finance::AccountingBaseController`.
  class PurchaseInvoiceValidationsController < ActionController::Base
    layout "public"

    before_action :authenticate_user!, only: [:dispute]

    def show
      @invoice = find_invoice
      return render :invalid, status: :not_found if @invoice.nil?
    end

    def confirm
      @invoice = find_invoice
      return render :invalid, status: :not_found if @invoice.nil?

      # Rien à valider (déjà tranchée, ou repartie en traitement entre-temps) :
      # on renvoie la page d'état, qui dit ce qui s'est passé, plutôt qu'un
      # « merci » qui mentirait.
      return render :show unless @invoice.to_validate?

      PurchaseInvoices::Validate.new(purchase_invoice: @invoice, user: current_user).approve!
      render :confirmed
    end

    # Refuser exige un compte : le motif doit être attribuable. On renvoie donc
    # vers la fiche admin, où le formulaire de contestation vit déjà.
    def dispute
      invoice = find_invoice
      return render :invalid, status: :not_found if invoice.nil?

      redirect_to finance_purchase_invoice_path(invoice)
    end

    private

    def find_invoice
      PurchaseInvoice.find_by_validation_token(params[:token])
    end

    def authenticate_user!
      return if current_user

      session[:user_return_to] = request.fullpath
      redirect_to new_user_session_path, alert: "Connecte-toi pour contester une facture."
    end

    def current_user
      @current_user ||= warden&.user
    end

    def warden = request.env["warden"]
  end
end
