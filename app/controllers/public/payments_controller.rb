class Public::PaymentsController < Public::BaseController
  def pay
    payment = Payment.find(params[:uuid])
    # Séjour annulé ou refusé : le lien d'acompte n'a plus d'objet. Les
    # paiements `pending` sont soft-deletés à l'annulation (donc introuvables
    # ici, 404) ; ce garde-fou couvre les paiements antérieurs à cette règle.
    if payment.stay&.canceled?
      return redirect_to failure_path(payment),
                         alert: "Ce séjour a été annulé : ce lien de paiement n'est plus valable. " \
                                "Écrivez-nous à sejours@les4sources.be."
    end
    service = Payments::PayService.new(payment_id: payment.id)
    if service.run
      redirect_to service.checkout_session_url,
                  allow_other_host: true,
                  data: { turbo: false }
    else
      redirect_to failure_path(payment),
                  alert: "Une erreur est survenue et celle-ci nous empêche de vous rediriger
                    vers le paiement en ligne. Veuillez nous contacter à sejours@les4sources.be."
    end
  end

  private

  # Stay-first (epic #26, Phase 2) : on renvoie le client là d'où il vient — la
  # page séjour quand le paiement y est rattaché, la page booking sinon (legacy).
  def failure_path(payment)
    if payment.stay&.token.present?
      public_stay_path(payment.stay.token)
    else
      public_booking_path(payment.booking.token)
    end
  end
end
