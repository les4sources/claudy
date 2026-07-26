# Poste de travail FACTURATION du Pôle Admin (Michael 2026-07-26).
#
# Remplace « Comptabilité / Tableau de bord », qui empilait quatre tableaux
# quasi identiques (hébergements / espaces × montant à définir / facture à
# fournir). Ici, une seule file de travail normalisée par `Invoicing::Queue`,
# et une action pour marquer une facture envoyée sans quitter la page.
class InvoicingController < BaseController
  def index
    @queue = Invoicing::Queue.new
  end

  # Bascule du statut de facture d'un réservable (« à fournir » ↔ « envoyée »).
  # La cible est POLYMORPHE : `kind` dit sur quel modèle taper, et n'accepte que
  # les clés connues de la file — un `params` fantaisiste lève plutôt que de
  # laisser passer un `constantize` arbitraire.
  def update_status
    model  = Invoicing::Queue.model_for(params[:kind])
    record = model.find(params[:id])
    status = params[:invoice_status].presence_in([Invoicing::Queue::REQUESTED,
                                                  Invoicing::Queue::SENT, ""])

    if status.nil?
      return redirect_to invoicing_path, alert: "Statut de facture invalide."
    end

    record.update(invoice_status: status)
    redirect_to invoicing_path, notice: notice_for(status)
  rescue KeyError
    redirect_to invoicing_path, alert: "Type de réservation inconnu."
  end

  private

  def notice_for(status)
    case status
    when Invoicing::Queue::SENT      then "Facture marquée comme envoyée."
    when Invoicing::Queue::REQUESTED then "Facture remise dans la file « à fournir »."
    else "Facture marquée comme non requise."
    end
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "accounting")
    @home_view = true
  end
end
