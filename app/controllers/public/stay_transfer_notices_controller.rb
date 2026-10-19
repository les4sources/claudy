module Public
  # « J'ai envoyé le virement » (Michael, 2026-10-19). Canal PUBLIC, scellé par
  # le jeton du séjour comme le paiement du solde : un jeton inconnu tombe en 404.
  #
  # Le clic prévient la compta par email (l'accueil en copie) et retient la date
  # et le montant annoncés. Tant qu'aucun paiement n'est encaissé depuis, la
  # page dit « virement signalé » et un nouveau POST n'écrit à personne : un
  # double clic ou un rechargement ne doit pas inonder la boîte de la compta.
  class StayTransferNoticesController < Public::BaseController
    def create
      stay = Stay.find_by!(token: params[:token])
      decorated = stay.decorate

      if decorated.show_transfer? && !decorated.transfer_notice_pending?
        amount_cents = decorated.transfer_amount_cents
        stay.update!(transfer_notified_at: Time.current, transfer_notified_cents: amount_cents)
        AdminMailer.transfer_announced(stay).deliver_later
      end

      redirect_to public_stay_path(stay.token, anchor: "paiement")
    rescue ActiveRecord::RecordNotFound
      raise ActionController::RoutingError, "Not Found"
    end
  end
end
