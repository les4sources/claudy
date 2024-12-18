class Public::PaymentsController < Public::BaseController
  def pay
    payment = Payment.find(params[:uuid])
    service = Payments::PayService.new(payment_id: payment.id)
    if service.run
      redirect_to service.checkout_session_url,
                  allow_other_host: true,
                  data: { turbo: false }
    else
      redirect_to public_booking_path(payment.stay.token),
                  alert: "Une erreur est survenue et celle-ci nous empêche de vous rediriger
                    vers le paiement en ligne. Veuillez nous contacter à sejours@les4sources.be."
    end
  end
end
