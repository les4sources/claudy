class ReservationMailer < ApplicationMailer
  # Récap post-réservation avec lien token stable de consultation (AC-T2-21).
  # Le breakdown affiché provient du même PricingModel.quote que l'UI (source
  # unique — AC-T2-17), recalculé depuis le Stay persisté.
  def confirmation_request(stay)
    @stay = stay
    @booking = stay.bookables.find { |b| b.is_a?(Booking) }
    # Stay-first (epic #26, Phase 2) : le lien de consultation envoyé au client
    # pointe sur la page séjour, pas sur la page booking — un séjour sans
    # hébergement n'a d'ailleurs pas de booking.
    @token = stay.token
    @quote = quote_from(stay)
    mail(
      to: stay.customer.email,
      subject: "Votre demande de réservation aux 4 Sources"
    )
  end

  # Second email du flux depuis l'inversion de l'ordre (issue #215, décision
  # Michael du 2026-08-31) : le Pôle Accueil a REGARDÉ la demande et la
  # pré-confirme. C'est ici — et seulement ici — que le client apprend le
  # montant de son acompte et reçoit son lien de paiement. Il remplace
  # l'ancienne demande d'acompte qui partait à la soumission du funnel, avant
  # tout regard humain.
  #
  # L'envoi est piloté par `Stays::PreConfirmer`, qui porte les garde-fous
  # (fourre-tout, absence d'email, rejeu) et appelle APRÈS le commit.
  def pre_confirmation(payment)
    @payment = payment
    @stay = payment.stay
    @token = @stay.token
    @pay_url = pay_public_payment_url(@payment, host: application_host)
    @stay_url = public_stay_url(@token, host: application_host)
    mail(
      to: @stay.customer.email,
      subject: "Votre demande est pré-confirmée — l'acompte finalise votre réservation",
      tag: "pre_confirmation"
    )
  end

  # Troisième email du flux, et le seul qui manquait (Malau, 2026-08-20) :
  # « votre séjour est confirmé, voici votre page ». Il tient la promesse faite
  # par `#pre_confirmation` (« le paiement de l'acompte confirme votre séjour »)
  # et rétablit ce que l'ancien `BookingMailer#booking_confirmed` faisait avant le passage
  # stay-first — mais sur le SÉJOUR, avec le lien `/sejour/:token` : un séjour
  # sans hébergement n'a pas de booking, donc pas de `public_booking_url`.
  #
  # L'envoi est piloté par `Stays::ConfirmationNotifier`, qui porte tous les
  # garde-fous (idempotence, fourre-tout, séjour passé). Ce mailer se contente
  # de composer.
  def stay_confirmed(stay)
    @stay = stay.decorate
    @stay_url = public_stay_url(stay.token, host: application_host)
    @balance_due_cents = stay.balance_due_cents
    @pending_payment = stay.payments.pending.where(payment_method: "card")
                           .order(:created_at).first
    mail(
      to: stay.customer.email,
      subject: "Votre séjour aux 4 Sources est confirmé 🌿",
      tag: "stay_confirmed"
    )
  end

  private

  def application_host
    ENV.fetch("APPLICATION_HOST", "app.les4sources.be")
  end

  def quote_from(stay)
    draft = Reservations::Draft.new(
      lodging_id: @booking&.lodging_id,
      arrival_date: stay.arrival_date,
      departure_date: stay.departure_date
    )
    draft.quote
  rescue StandardError
    nil
  end
end
