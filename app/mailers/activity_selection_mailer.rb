class ActivitySelectionMailer < ApplicationMailer
  MALAU_EMAIL = "malau@les4sources.be".freeze

  # Email envoyé au client ~1 mois avant son arrivée pour sélectionner les activités.
  def invitation(stay)
    @stay = stay
    @booking = stay.bookables.find { |b| b.is_a?(Booking) }
    @selection_url = public_activity_selection_url(stay.activity_selection_token,
                                                   host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be"))
    mail(
      to: stay.customer.email,
      subject: "Réservez vos activités pour votre séjour aux 4 Sources"
    )
  end

  # Confirmation au client après sélection.
  def confirmation(stay)
    @stay = stay
    @bookings = stay.experience_bookings.includes(experience_availability: :experience).active
    @selection_url = public_activity_selection_url(stay.activity_selection_token,
                                                   host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be"))
    mail(
      to: stay.customer.email,
      subject: "Vos activités aux 4 Sources — confirmation de demande"
    )
  end

  # Notification au client quand le porteur VALIDE son activité (epic #55, Phase 2).
  def booking_confirmed(experience_booking)
    @booking = experience_booking
    @stay = experience_booking.stay
    @experience = experience_booking.experience
    mail(
      to: @stay.customer.email,
      subject: "Votre activité « #{@experience.name} » est confirmée"
    )
  end

  # Notification au client quand le porteur REFUSE son activité (epic #55,
  # Phase 2) : on transmet la raison et on invite à re-choisir un créneau via
  # la page de sélection à jeton existante.
  def booking_refused(experience_booking)
    @booking = experience_booking
    @stay = experience_booking.stay
    @experience = experience_booking.experience
    @reason = experience_booking.refusal_reason
    @selection_url = public_activity_selection_url(@stay.activity_selection_token,
                                                   host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be"))
    mail(
      to: @stay.customer.email,
      subject: "Votre activité « #{@experience.name} » n'a pas pu être retenue"
    )
  end

  # Email aux animateurs concernés (un par activité demandée).
  def animateur_notification(stay)
    @stay = stay
    @bookings = stay.experience_bookings.includes(experience_availability: :experience).active
    # Hôte des liens de validation/refus à jeton (epic #55, Phase 2) — même
    # source que les autres liens de ce mailer, pour rester stable en test.
    @link_host = ENV.fetch("APPLICATION_HOST", "app.les4sources.be")
    return if @bookings.empty?

    animateur_emails = @bookings.filter_map { |b| b.experience.human&.email }.uniq.compact
    return if animateur_emails.empty?

    mail(
      to: animateur_emails,
      cc: MALAU_EMAIL,
      subject: "Demande d'activité — séjour #{stay.arrival_date&.strftime('%-d/%m/%Y')}"
    )
  end
end
