module Stays
  # Pré-confirmation d'une demande par le Pôle Accueil (issue #215, décision
  # Michael du 2026-08-31).
  #
  # POURQUOI CE SERVICE EXISTE. Le funnel B2C demandait l'acompte à la
  # soumission : le client payait AVANT que qui que ce soit aux 4 Sources ait
  # regardé sa demande, alors que le séjour restait `pending` et que l'équipe
  # pouvait très bien devoir refuser, décaler les dates ou réajuster le prix.
  # On inverse l'ordre. Le formulaire n'encaisse plus rien, il enregistre une
  # demande ; c'est ce service — déclenché par un CLIC humain sur la fiche
  # séjour, jamais automatiquement — qui crée l'acompte et l'envoie au client.
  #
  # CE QU'IL POSE. Un `Payment` `pending`/`card` du montant validé par le Pôle
  # Accueil (l'acompte est AJUSTABLE : 50 % n'est qu'un préremplissage), et le
  # statut `pre_confirmed` sur le séjour ET sur ses réservables. Ce statut est un
  # état d'ATTENTE DE PAIEMENT, entre `pending` (personne n'a regardé) et
  # `confirmed` (acompte encaissé).
  #
  # ⚠️ IL BLOQUE DÉSORMAIS LES DATES (décision Michael du 2026-09-08 — renverse
  # le « il ne pose aucun veto » d'origine). L'ancienne règle « tant que l'argent
  # n'est pas là, les dates ne sont pas garanties » laissait pré-confirmer DEUX
  # demandes sur les mêmes dates, puis les confirmer toutes les deux : l'acompte
  # du second client tombait sur un gîte déjà pris. Une pré-confirmation est un
  # engagement de l'équipe — cf. `Stay::BLOCKING_STATUSES`.
  #
  # Deux conséquences, toutes deux portées ici :
  #   1. on VÉRIFIE la disponibilité avant de poser l'acompte (le séjour a pu
  #      dormir des jours dans la file pendant qu'un autre était confirmé) ;
  #   2. on PROPAGE `pre_confirmed` aux réservables, comme le fait
  #      `QuickStatusUpdater` — le veto lit le statut des bookables, pas celui
  #      du séjour, donc sans propagation la constante ne servirait à rien.
  #
  # CE QU'IL NE FAIT PAS. Il ne confirme rien. La bascule vers `confirmed` est
  # déclenchée par l'encaissement Stripe (`Stripe::CompletedCheckoutService`),
  # qui passe par `Stays::QuickStatusUpdater` — lequel repropage correctement
  # depuis `pre_confirmed`, tout comme le retour en `pending` (« Repasser en
  # attente »), qui LIBÈRE les dates.
  #
  # HORS TRANSACTION. L'email part APRÈS le commit, comme
  # `Stays::ConfirmationNotifier` : un incident Postmark ne doit pas annuler une
  # pré-confirmation. L'échec d'envoi est capturé (Sentry) et lisible via
  # `#email_error` — le Payment et le statut restent posés, l'équipe peut
  # renvoyer le lien à la main.
  class PreConfirmer
    def self.call(stay:, amount_cents:)
      new(stay: stay, amount_cents: amount_cents).run
    end

    attr_reader :stay, :payment, :error_message, :email_error

    def initialize(stay:, amount_cents:)
      @stay = stay
      @amount_cents = amount_cents.to_i
    end

    # @return [Boolean] true si la pré-confirmation est posée (l'email peut
    #   avoir échoué ; voir `#email_error`).
    def run
      return false unless valid?

      Stay.transaction do
        @payment = Payment.create!(
          stay: stay,
          booking: lodging_booking,
          amount_cents: @amount_cents,
          status: "pending",
          payment_method: "card"
        )
        stay.update!(status: "pre_confirmed")
        propagate_to_bookables!
      end

      deliver_email!
      true
    rescue ActiveRecord::RecordInvalid => e
      @error_message = e.message
      false
    end

    # Montant PRÉREMPLI proposé au Pôle Accueil : le taux d'acompte du barème
    # appliqué à la part hébergement/espaces — les activités en sont exclues,
    # elles se règlent avec le solde une fois validées par leur porteur. Arrondi
    # à l'euro supérieur : un acompte à 372,53 € n'a aucun sens sur un courrier.
    def self.suggested_amount_cents(stay)
      base = stay.lodging_and_spaces_amount_cents.to_i
      return 0 unless base.positive?

      (base * Pricing::Catalog.default_deposit_rate / 100.0).ceil * 100
    end

    private

    # Le `Payment` porte le séjour dans tous les cas ; le booking d'hébergement
    # n'est qu'une référence de commodité pour le canal historique, et il peut
    # être absent (séjour camping / espaces seuls).
    def lodging_booking
      stay.stay_items.find { |item| item.bookable_type == "Booking" }&.bookable
    end

    def valid?
      return refuse("Ce séjour a déjà été pré-confirmé.") if stay.status == "pre_confirmed"
      return refuse("Seule une demande en attente peut être pré-confirmée.") unless stay.status == "pending"
      return refuse("Ce séjour est supprimé.") if stay.deleted_at.present?
      return refuse("Ce client n'a pas d'adresse email.") if stay.customer&.email.blank?
      # Fourre-tout (générique ou par OTA) : l'adresse est une boîte MAISON, pas
      # celle d'un client. Lui demander un acompte écrirait aux 4 Sources à
      # propos du séjour de quelqu'un d'autre.
      return refuse("Ce séjour est rattaché à un client fourre-tout.") if stay.customer&.catch_all?
      return refuse("Le montant de l'acompte doit être supérieur à 0 €.") unless @amount_cents.positive?

      if @amount_cents > max_amount_cents
        return refuse("Le montant de l'acompte ne peut pas dépasser le total dû du séjour " \
                      "(#{format_euros(max_amount_cents)}).")
      end

      # Dernier filet AVANT de poser l'acompte (Michael 2026-09-08). Une demande
      # peut avoir attendu des jours dans la file pendant qu'un autre séjour
      # était confirmé sur les mêmes dates. Puisque la pré-confirmation bloque
      # désormais le calendrier, la poser sur des dates déjà prises créerait
      # exactement le double-booking qu'on cherche à empêcher — et le client
      # recevrait une demande d'acompte pour un gîte qui n'est plus libre.
      if (pris = unavailable_resources).any?
        return refuse("Ces dates ne sont plus disponibles pour #{pris.to_sentence} : " \
                      "pré-confirmer créerait un doublon. Modifiez la composition du séjour, " \
                      "ou refusez la demande.")
      end

      true
    end

    # Ressources du séjour dont les dates sont déjà tenues par QUELQU'UN D'AUTRE,
    # décrites pour l'affichage. Vide quand tout passe.
    #
    # L'occupation du séjour LUI-MÊME est toujours exclue : ses réservables sont
    # encore `pending` à cet instant (donc non bloquants), mais on ne s'appuie
    # pas là-dessus — un séjour dont un bookable aurait déjà été passé à la main
    # en `confirmed` se bloquerait lui-même, et l'action deviendrait impossible
    # sans explication.
    def unavailable_resources
      (unavailable_lodgings + unavailable_spaces).uniq
    end

    # Hébergements. On délègue à `Stays::LodgingAvailability` — SOURCE UNIQUE de
    # la dispo hébergement, déjà utilisée par la validation admin et par la
    # demande de modification client : elle porte le contrat de dates (issue
    # #94), le mode chambres seules, les `Unavailability` et l'exclusion des
    # Booking du séjour. Un séjour peut porter PLUSIEURS Booking (multi-gîtes) :
    # on construit un draft minimal par Booking plutôt que de ne regarder que le
    # premier.
    def unavailable_lodgings
      lodging_bookings.filter_map do |booking|
        next if booking.lodging_id.blank? || booking.from_date.blank? || booking.to_date.blank?

        draft = Reservations::Draft.new(
          lodging_id:     booking.lodging_id,
          booking_type:   booking.rooms_mode? ? "rooms" : "lodging",
          room_ids:       booking.rooms_mode? ? booking.reservations.map(&:room_id).uniq : [],
          arrival_date:   booking.from_date,
          departure_date: booking.to_date
        )
        next if Stays::LodgingAvailability.call(stay: stay, draft: draft)

        "#{booking.lodging&.name.presence || 'l’hébergement'} " \
          "(#{format_date(booking.from_date)} → #{format_date(booking.to_date)})"
      end
    end

    # Espaces, JOUR PAR JOUR (une salle se loue à la journée, et un espace
    # partagé — camping Bois, pâtures — a une capacité > 1). Même règle que
    # `Space#booked_on?`, avec exclusion des SpaceBooking du séjour.
    def unavailable_spaces
      own_ids = own_space_booking_ids

      space_reservations.filter_map do |reservation|
        space = reservation.space
        next if space.nil? || reservation.date.blank?

        scope = SpaceReservation.includes(:space_booking)
                                .where(date: reservation.date, space: space.id,
                                       space_booking: { status: Stay::BLOCKING_STATUSES })
        scope = scope.where.not(space_booking: { id: own_ids }) if own_ids.any?
        next if scope.count < space.capacity

        "#{space.name} (#{format_date(reservation.date)})"
      end
    end

    def lodging_bookings
      stay.stay_items.select { |item| item.bookable_type == "Booking" }.filter_map(&:bookable)
    end

    def stay_space_bookings
      stay.stay_items.select { |item| item.bookable_type == "SpaceBooking" }.filter_map(&:bookable)
    end

    def own_space_booking_ids
      stay_space_bookings.map(&:id)
    end

    def space_reservations
      stay_space_bookings.flat_map { |sb| sb.space_reservations.to_a }
    end

    # Propagation du statut aux réservables — miroir de
    # `Stays::QuickStatusUpdater#propagate_to_bookables!`. Sans elle, le veto
    # (qui lit le statut des bookables) ne verrait jamais la pré-confirmation.
    #
    # `skip_customer_notification` : même contrat anti-spam que le toggle de
    # statut interne. Aucun callback des bookables ne réagit d'ailleurs à
    # `pre_confirmed` (Booking et SpaceBooking ne notifient que sur `confirmed`,
    # `declined`, `canceled`) — le garde-fou est là par principe, pas par
    # nécessité. Le SEUL email du flux est celui du client, envoyé plus bas,
    # APRÈS le commit.
    def propagate_to_bookables!
      stay.bookables.each do |bookable|
        next unless bookable.respond_to?(:status)

        bookable.skip_customer_notification = true if bookable.respond_to?(:skip_customer_notification=)
        bookable.update!(status: "pre_confirmed")
      end
    end

    def format_date(date) = I18n.l(date, format: :long).strip

    # Plafond = le reste dû EXIGIBLE. On ne demande jamais un acompte supérieur
    # à ce que le séjour coûte — la saisie est libre, pas les invariants.
    def max_amount_cents
      stay.balance_due_cents.to_i
    end

    def deliver_email!
      ReservationMailer.pre_confirmation(@payment).deliver_now
    rescue StandardError => e
      Sentry.capture_exception(e)
      @email_error = "La pré-confirmation est enregistrée mais l'email n'a pas pu être envoyé (#{e.class})."
    end

    def refuse(message)
      @error_message = message
      false
    end

    def format_euros(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, unit: "€", format: "%n %u", precision: 2)
    end
  end
end
