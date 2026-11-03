module Public
  # « J'ai envoyé le virement » (Michael, 2026-10-19). Canal PUBLIC, scellé par
  # le jeton du séjour comme le paiement du solde : un jeton inconnu tombe en 404.
  #
  # Le clic prévient la compta par email (l'accueil en copie) et retient la date
  # et le montant annoncés. Tant qu'aucun paiement n'est encaissé depuis, la
  # page dit « virement signalé » et un nouveau POST n'écrit à personne : un
  # double clic ou un rechargement ne doit pas inonder la boîte de la compta.
  #
  # Virement partiel (Michael, 2026-11-03) : une cliente avait viré une partie
  # seulement, et le bouton annonçait d'office le montant demandé. Le client
  # indique maintenant le montant qu'il a viré (prérempli avec le montant
  # demandé) et peut le corriger tant que le virement n'est pas arrivé : la
  # compta reçoit alors un email « montant corrigé ». Même montant = rien.
  class StayTransferNoticesController < Public::BaseController
    # Au-delà, c'est une faute de frappe (un IBAN collé dans le champ…).
    MAX_AMOUNT_CENTS = 10_000_000

    def create
      stay = Stay.find_by!(token: params[:token])
      decorated = stay.decorate

      if decorated.show_transfer?
        amount_cents = announced_amount_cents || decorated.transfer_amount_cents

        if !decorated.transfer_notice_pending?
          stay.update!(transfer_notified_at: Time.current, transfer_notified_cents: amount_cents)
          AdminMailer.transfer_announced(stay).deliver_later
        elsif amount_cents != stay.transfer_notified_cents
          stay.update!(transfer_notified_cents: amount_cents)
          AdminMailer.transfer_announced(stay, corrected: true).deliver_later
        end
      end

      redirect_to public_stay_path(stay.token, anchor: "paiement")
    rescue ActiveRecord::RecordNotFound
      raise ActionController::RoutingError, "Not Found"
    end

    private

    # « 150 », « 150,50 », « 1 250,00 € » ou « 150.5 » → centimes. Vide,
    # illisible ou nul → nil : on retombe sur le montant demandé, comme avant.
    def announced_amount_cents
      raw = params[:amount].to_s.gsub(/[^\d,.]/, "")
      return if raw.blank?

      # Un séparateur suivi d'un ou deux chiffres en fin de nombre est la
      # décimale ; tous les autres sont des milliers (« 1.250 » = 1250 €).
      if (match = raw.match(/\A(.*?)[,.](\d{1,2})\z/))
        integer, decimals = match[1].delete(",."), match[2]
      else
        integer, decimals = raw.delete(",."), ""
      end

      cents = integer.to_i * 100 + decimals.ljust(2, "0")[0, 2].to_i
      cents if cents.positive? && cents <= MAX_AMOUNT_CENTS
    end
  end
end
