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
  # statut `pre_confirmed` sur le séjour. Ce statut est un état d'ATTENTE DE
  # PAIEMENT, entre `pending` (personne n'a regardé) et `confirmed` (acompte
  # encaissé) — il ne pose aucun veto de disponibilité, et c'est voulu : tant
  # que l'argent n'est pas là, les dates ne sont pas garanties.
  #
  # CE QU'IL NE FAIT PAS. Il ne confirme rien. La bascule vers `confirmed` est
  # déclenchée par l'encaissement Stripe (`Stripe::CompletedCheckoutService`),
  # qui passe par `Stays::QuickStatusUpdater` pour propager le statut aux
  # réservables — sans quoi le veto de dispo ne se poserait jamais.
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

      true
    end

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
