module Public
  # Paiement du SOLDE exigible d'un séjour (epic #55, Phase 3). Canal PUBLIC :
  # l'autorisation repose entièrement sur le JETON du séjour — pas de Devise.
  # Seul le détenteur du lien /sejour/:token peut déclencher le paiement de SON
  # séjour ; un jeton inconnu tombe en 404 (jamais d'énumération d'IDs).
  #
  # Action POST (elle écrit : crée/rafraîchit un Payment `pending`), puis
  # redirige vers la session Stripe Checkout produite par `PayService`.
  class StayBalancePaymentsController < Public::BaseController
    layout "public_sheet"

    def create
      stay = Stay.find_by!(token: params[:token])
      service = Payments::CreateBalanceService.new(stay: stay)

      if service.run
        redirect_to service.checkout_session_url,
                    allow_other_host: true,
                    data: { turbo: false }
      else
        redirect_to public_stay_path(stay.token),
                    alert: service.error_message(default: "Le paiement du solde n'a pas pu être initialisé. Veuillez nous contacter à sejours@les4sources.be.")
      end
    rescue ActiveRecord::RecordNotFound
      raise ActionController::RoutingError, "Not Found"
    end
  end
end
