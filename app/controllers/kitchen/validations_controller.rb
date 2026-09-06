module Kitchen
  # Canal JETON de validation des prestations de cuisine (epic #219, phase 4),
  # calqué sur celui des activités.
  #
  # Choix de sécurité, les mêmes qu'ailleurs :
  #   * ACCEPTER = mutation bénigne. On ne mute JAMAIS sur un GET, qu'un
  #     antivirus ou un proxy mail peut précharger. Le lien mène à une page de
  #     confirmation dont le bouton POSTe (protégé par CSRF).
  #   * REFUSER = exige un motif, donc un compte. Le lien force la connexion
  #     (n'importe quel compte : ils sont partagés) puis renvoie vers le
  #     formulaire de motif du canal admin.
  class ValidationsController < ActionController::Base
    layout "public"

    before_action :authenticate_user!, only: [:refuse]

    def show
      @order = find_order
      return render :invalid, status: :not_found if @order.nil?
    end

    def confirm
      @order = find_order
      return render :invalid, status: :not_found if @order.nil?

      # Rien à accepter (déjà répondu, ou demande annulée entre-temps) : on
      # renvoie la page d'état, qui dit ce qui s'est passé, plutôt qu'un « merci »
      # qui mentirait.
      return render :show unless @order.pending? && !@order.cancelled?

      @order.accept!
      render :confirmed
    end

    def refuse
      order = find_order
      return render :invalid, status: :not_found if order.nil?

      redirect_to new_refusal_kitchen_order_path(order)
    end

    private

    def find_order
      order = MealOrder.find_by_validation_token(params[:token])
      order&.decorate
    end
  end
end
