module Stays
  # Email « votre séjour est confirmé » — le chaînon manquant du flux client.
  #
  # POURQUOI CE SERVICE EXISTE. Le client recevait « votre demande est
  # enregistrée » (`ReservationMailer#confirmation_request`), puis « acompte bien
  # reçu, notre équipe valide votre demande » (`#deposit_received`), et plus rien
  # quand l'équipe validait effectivement. La promesse du 2e email n'était donc
  # jamais tenue. La cause : depuis le passage stay-first (issue #99, juillet
  # 2026), plus aucun chemin admin ne fait passer un `Booking` en `confirmed`
  # avec sa notification vivante — `Stays::QuickStatusUpdater` et
  # `Stays::AdminUpdater` coupent tous deux l'email client, à raison (ils
  # propagent un statut ou réconcilient une composition, ce ne sont pas des
  # actes de communication). L'email de confirmation appartient au SÉJOUR : il
  # se déclenche ici, une fois, sur la bascule.
  #
  # IDEMPOTENCE. `stays.confirmation_email_sent_at` porte l'unique garde-fou :
  # un aller-retour pending → confirmed → pending → confirmed ne renvoie pas
  # l'email. Le renvoi manuel (`force: true`, bouton de la fiche admin) est le
  # seul à passer outre — c'est une décision humaine explicite.
  #
  # HORS TRANSACTION. L'appel se fait TOUJOURS après le commit : un timeout
  # Postmark ne doit jamais annuler la confirmation d'un séjour. Toute erreur
  # d'envoi est capturée (Sentry) et rendue en `false` — le statut reste posé,
  # l'équipe voit que l'email n'est pas parti et peut le renvoyer à la main.
  class ConfirmationNotifier
    # Un séjour déjà terminé ne se « confirme » plus au sens du client : quand
    # Malau régularise un vieux séjour dans le CRUD, lui écrire « votre séjour
    # est confirmé, préparez vos affaires » n'a aucun sens. Les envois
    # automatiques s'arrêtent donc au départ ; le renvoi manuel, lui, ne
    # connaît pas cette borne (l'équipe sait ce qu'elle fait).
    def self.call(stay, force: false)
      new(stay: stay, force: force).run
    end

    attr_reader :stay, :skip_reason

    def initialize(stay:, force: false)
      @stay = stay
      @force = force
    end

    # @return [Boolean] true si l'email est effectivement parti.
    def run
      return false unless deliverable?

      ReservationMailer.stay_confirmed(stay).deliver_now
      # `update_column` : on horodate SANS toucher aux validations ni aux
      # callbacks du séjour — l'envoi d'un email n'est pas une modification
      # métier et ne doit pas repasser par `recompute_aggregates!`.
      stay.update_column(:confirmation_email_sent_at, Time.current)
      true
    rescue StandardError => e
      Sentry.capture_exception(e)
      @skip_reason = "L'email n'a pas pu être envoyé (#{e.class})."
      false
    end

    private

    def deliverable?
      return skip("Le séjour n'est pas confirmé.") unless stay.status == "confirmed"
      return skip("Le séjour est supprimé.") if stay.deleted_at.present?
      return skip("Ce client n'a pas d'adresse email.") if customer_email.blank?
      # Fourre-tout (générique ou par OTA) : l'adresse est une boîte MAISON, pas
      # celle d'un client. Lui envoyer « votre séjour est confirmé » écrirait
      # aux 4 Sources à propos du séjour de quelqu'un d'autre.
      return skip("Ce séjour est rattaché à un client fourre-tout.") if stay.customer&.catch_all?

      return true if @force

      return skip("L'email de confirmation a déjà été envoyé.") if stay.confirmation_email_sent_at.present?
      return skip("Ce séjour est déjà terminé.") if past?

      true
    end

    def past?
      stay.departure_date.present? && stay.departure_date < Date.current
    end

    def customer_email
      stay.customer&.email
    end

    def skip(reason)
      @skip_reason = reason
      false
    end
  end
end
