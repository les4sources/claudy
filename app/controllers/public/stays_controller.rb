module Public
  # Page client du séjour-composite (epic #26, Phase 1). Accessible sans Devise,
  # via le jeton général du séjour — comme la page booking historique, qui reste
  # en place pour les liens déjà envoyés.
  class StaysController < Public::BaseController
    layout "public_sheet"

    def show
      @stay = Stay.find_by!(token: params[:token]).decorate
      @payments = PaymentDecorator.decorate_collection(@stay.payments.order(created_at: :asc))
    rescue ActiveRecord::RecordNotFound
      raise ActionController::RoutingError, "Not Found"
    end
  end
end
