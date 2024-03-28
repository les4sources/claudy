class Public::PaymentsController < Public::BaseController
  layout "public_sheet"

  def pay
    payment = Payment.find(params[:id])
    service = Payments::PayService.new(payment_id: payment.id)
    if service.run
      redirect_to service.checkout_session_url,
                  allow_other_host: true
    else
      redirect_to public_booking_path(@payment.booking),
                  notice: "Une erreur est survenue. Veuillez nous contacter à contact@les4sources.be."
    end
  end

  private

end
