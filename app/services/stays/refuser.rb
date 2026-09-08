module Stays
  # Refus d'une demande de séjour par le Pôle Accueil (décision Michael du
  # 2026-09-08).
  #
  # POURQUOI CE SERVICE EXISTE. Le flux ne savait dire que « oui ». Pour dire
  # « non », l'équipe cliquait « Annuler le séjour »
  # (`Stays::QuickStatusUpdater`), qui n'écrit RIEN au client : le contrat
  # anti-spam du toggle de statut interne est juste pour un aller-retour de
  # gestion, mais désastreux ici — le client qui a rempli le funnel n'apprenait
  # jamais que sa demande était refusée. Il attendait une pré-confirmation qui
  # ne venait pas.
  #
  # Refuser est donc devenu une ACTION À PART ENTIÈRE, distincte de l'annulation
  # d'un séjour existant : elle exige un MOTIF, elle l'envoie au client, et elle
  # ferme proprement le dossier.
  #
  # CE QU'ELLE FAIT, dans une seule transaction :
  #   1. passe le séjour en `canceled` en RÉUTILISANT `QuickStatusUpdater` —
  #      c'est lui qui porte la propagation du statut aux réservables (donc la
  #      LIBÉRATION des dates, essentielle depuis que `pre_confirmed` les
  #      bloque) et l'annulation des activités encore actives ;
  #   2. neutralise les `Payment` encore `pending` — typiquement l'acompte posé
  #      par une pré-confirmation. C'est `QuickStatusUpdater` qui le fait, pour
  #      TOUTE annulation (« Annuler le séjour » compris) : un lien d'acompte
  #      resté payable après l'annulation aurait reconfirmé le séjour à
  #      l'encaissement. Soft-delete, jamais un `paid` — voir là-bas ;
  #   3. horodate le refus et son motif dans la note INTERNE du séjour — sans
  #      quoi, trois mois plus tard, personne ne sait pourquoi ce dossier est
  #      rouge.
  #
  # HORS TRANSACTION. L'email part APRÈS le commit, comme `PreConfirmer` et
  # `ConfirmationNotifier` : un incident Postmark ne doit pas annuler un refus
  # déjà décidé. L'échec d'envoi est capturé (Sentry) et lisible via
  # `#email_error` — le refus tient, l'équipe peut écrire à la main.
  class Refuser
    # Une demande PRÉ-CONFIRMÉE reste refusable (Michael 2026-09-08) : tant que
    # l'acompte n'est pas payé, rien n'est acquis, et c'est précisément le cas
    # où le refus est le plus utile — le séjour bloque des dates qu'il faut
    # rendre. Un séjour CONFIRMÉ, lui, ne se « refuse » pas : il s'annule, avec
    # les conséquences financières que cela suppose.
    REFUSABLE_STATUSES = %w[pending pre_confirmed].freeze

    # Séparateur de la note interne — même convention que `MergeOriginNotes`,
    # qui est l'autre écrivain de ce champ.
    NOTE_SEPARATOR = Stays::MergeOriginNotes::SEPARATOR

    # Échec dans la transaction : sert uniquement à la faire rouler en arrière
    # en remontant le message du service appelé.
    class RefusalFailed < StandardError; end

    def self.call(stay:, reason:, by: nil)
      new(stay: stay, reason: reason, by: by).run
    end

    attr_reader :stay, :reason, :error_message, :email_error, :email_recipient

    def initialize(stay:, reason:, by: nil)
      @stay = stay
      @reason = reason.to_s.strip
      @by = by
    end

    # @return [Boolean] true si le refus est enregistré (l'email peut avoir
    #   échoué ou ne pas avoir lieu d'être ; voir `#email_error` et
    #   `#email_recipient`).
    def run
      return false unless valid?

      Stay.transaction do
        updater = Stays::QuickStatusUpdater.new(stay: stay, status: "canceled")
        raise RefusalFailed, updater.error_message unless updater.run

        append_internal_note!
      end

      deliver_email!
      true
    rescue RefusalFailed => e
      @error_message = e.message.presence || "Le refus n'a pas pu être enregistré."
      false
    rescue ActiveRecord::RecordInvalid => e
      @error_message = e.message
      false
    end

    private

    def valid?
      # Le motif part TEL QUEL au client : c'est la seule chose qu'il lira pour
      # comprendre. Un refus muet ne vaut pas mieux que l'ancienne annulation
      # silencieuse — d'où l'obligation, ici et pas seulement dans le formulaire.
      return refuse("Un motif de refus est obligatoire : il est envoyé au client.") if reason.blank?
      return refuse("Ce séjour est supprimé.") if stay.deleted_at.present?

      unless REFUSABLE_STATUSES.include?(stay.status.to_s)
        return refuse("Seule une demande en attente ou pré-confirmée peut être refusée " \
                      "(ce séjour est « #{stay.status.presence || 'sans statut'} »).")
      end

      true
    end

    # Ligne horodatée dans la note INTERNE (colonne `stays.notes`, texte brut,
    # jamais publique). `update!` et non `update_column` : le refus EST un acte
    # éditorial, il doit laisser une version PaperTrail.
    def append_internal_note!
      ligne = "⛔ Demande refusée le #{I18n.l(Date.current, format: :long).strip} " \
              "par #{author_label} — motif : #{reason}"
      parts = [stay.notes.to_s.strip.presence, ligne].compact

      stay.update!(notes: parts.join(NOTE_SEPARATOR))
    end

    # Prénom de la personne qui refuse. `Human` ne porte qu'une colonne `name`
    # complète : on en prend le premier mot, comme le reste de l'app affiche les
    # membres entre eux. Repli sur l'email, jamais sur l'id brut.
    def author_label
      human_name = @by&.human&.name.presence
      return human_name.split.first if human_name

      @by&.email.presence || "l'équipe"
    end

    # Garde-fous IDENTIQUES à ceux de `PreConfirmer` : un client sans email n'a
    # rien à recevoir, et un client FOURRE-TOUT (générique ou par OTA) porte une
    # adresse MAISON — lui écrire enverrait aux 4 Sources le refus du séjour de
    # quelqu'un d'autre.
    def deliver_email!
      return if stay.customer&.email.blank?
      return if stay.customer.catch_all?

      ReservationMailer.request_refused(stay, reason).deliver_now
      @email_recipient = stay.customer.email
    rescue StandardError => e
      Sentry.capture_exception(e)
      @email_error = "Le refus est enregistré mais l'email n'a pas pu être envoyé (#{e.class})."
    end

    def refuse(message)
      @error_message = message
      false
    end
  end
end
