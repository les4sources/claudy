class ReservationMailer < ApplicationMailer
  # Même boîte que `StayChangeRequestMailer` : le Pôle Accueil lit tout le flux
  # séjour au même endroit.
  TEAM_EMAIL = "sejours@les4sources.be".freeze

  # Récap post-réservation avec lien token stable de consultation (AC-T2-21).
  # Le breakdown affiché provient du même PricingModel.quote que l'UI (source
  # unique — AC-T2-17), recalculé depuis le Stay persisté.
  def confirmation_request(stay)
    @stay = stay
    # Stay-first (epic #26, Phase 2) : le lien de consultation envoyé au client
    # pointe sur la page séjour, pas sur la page booking — un séjour sans
    # hébergement n'a d'ailleurs pas de booking.
    @token = stay.token
    @quote = quote_from(stay)
    # Garde issue #232 : un client peut vivre sans email. On ne compte pas sur
    # les seuls appelants — un mailer sans destinataire lèverait, ici il se tait.
    return if stay.customer&.email.blank?

    mail(
      to: stay.customer.email,
      subject: "Votre demande de réservation aux 4 Sources"
    )
  end

  # Email d'ÉQUIPE à CHAQUE nouvelle demande du funnel (décision Michael du
  # 2026-09-08). Jusqu'ici sejours@ ne recevait qu'une COPIE CACHÉE de l'accusé
  # de réception client : un email écrit POUR le client, sans la composition
  # détaillée, sans la note d'espaces, sans lien vers la fiche. Le Pôle Accueil
  # doit pouvoir juger une demande depuis sa boîte, puis n'avoir qu'un clic à
  # faire pour agir.
  #
  # Cet email ne porte AUCUNE action. Pré-confirmer et refuser vivent sur la
  # fiche séjour — seul endroit où l'état du séjour est vrai au moment du clic,
  # et où les deux flux se croisent (une demande peut avoir bougé entre l'envoi
  # de cet email et sa lecture).
  def team_new_request(stay)
    @stay        = stay.decorate
    @spaces_note = spaces_note_for(stay)
    @stay_url    = stay_url(stay, host: application_host)

    # `bcc` par défaut (ApplicationMailer) = sejours@, soit le destinataire même
    # de cet email : sans ce `nil`, chaque demande arriverait en double dans la
    # boîte du Pôle Accueil.
    mail(to: TEAM_EMAIL, bcc: nil, subject: team_new_request_subject)
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
    # Garde issue #232 : un client peut vivre sans email. On ne compte pas sur
    # les seuls appelants — un mailer sans destinataire lèverait, ici il se tait.
    return if @stay.customer&.email.blank?

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
    # Garde issue #232 : un client peut vivre sans email. On ne compte pas sur
    # les seuls appelants — un mailer sans destinataire lèverait, ici il se tait.
    return if stay.customer&.email.blank?

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

  # « Nouvelle demande de séjour #1503 — Camille Martin (Les Copains) ·
  # 5 → 9 oct. 2026 · 1 685 € » : l'objet doit suffire à trier une boîte en
  # diagonale, sans ouvrir l'email.
  def team_new_request_subject
    who   = @stay.customer&.name.presence || "Client sans nom"
    group = team_group_name
    who   = "#{who} (#{group})" if group.present?

    details = [who, short_date_range(@stay), @stay.formatted_total].compact_blank
    "Nouvelle demande de séjour ##{@stay.id} — #{details.join(' · ')}"
  end

  # Le nom de groupe vit sur les réservables (Booking, SpaceBooking…), jamais
  # sur le séjour : on prend le premier renseigné.
  def team_group_name
    @stay.bookables.filter_map { |b| b.try(:group_name).presence }.first
  end

  # Forme COURTE de la plage — « 5 → 9 oct. 2026 » — où ce qui est commun aux
  # deux bornes ne s'écrit qu'une fois. Le `date_range` du décorateur est fait
  # pour une fiche ; dans un objet d'email il mange la place de ce qui suit.
  def short_date_range(stay)
    from = stay.arrival_date
    to   = stay.departure_date
    return nil if from.blank? && to.blank?
    return short_date(from.presence || to) if from.blank? || to.blank? || from == to
    return "#{short_date(from)} → #{short_date(to)}" if from.year != to.year
    return "#{from.day} → #{short_date(to)}" if from.month == to.month

    "#{I18n.l(from, format: '%-d %b')} → #{short_date(to)}"
  end

  def short_date(date) = I18n.l(date, format: "%-d %b %Y")

  # Précision libre laissée par le client sur son besoin d'espace : elle est
  # persistée dans la note INTERNE du SpaceBooking, préfixée par
  # `SPACES_NOTE_PREFIX`. Une note SANS ce préfixe est une note d'équipe — elle
  # n'a rien à faire dans un email de demande entrante.
  def spaces_note_for(stay)
    stay.stay_items
        .filter_map { |item| item.bookable&.notes.presence if item.bookable_type == "SpaceBooking" }
        .find { |note| note.start_with?(SpaceComposition::SPACES_NOTE_PREFIX) }
  end

  # Devis du séjour persisté. La reconstruction COMPLÈTE (décision Michael du
  # 2026-09-08) remplace un Draft qui ne portait que `lodging_id` et les dates :
  # salles, camping, hamacs et chien en étaient absents, et le client lisait un
  # total plus bas que le sien — 1 265 € annoncés pour un séjour à 1 685 €.
  # `DraftReconstructor` est déjà la reconstruction de référence : l'édition
  # admin et la modification client s'en servent.
  def quote_from(stay)
    Stays::DraftReconstructor.call(stay).quote
  rescue StandardError
    nil
  end
end
