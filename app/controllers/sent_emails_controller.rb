# Consultation d'un email envoyé à un client — rendu dans la modale Turbo de la
# fiche client (`customers#show`). Lecture seule : le journal ne s'édite pas.
class SentEmailsController < BaseController
  layout "modal"

  def show
    @customer = Customer.find(params[:customer_id])
    @sent_email = @customer.sent_emails.find(params[:id])
  end

  private

  # Fragment de modale : aucun presenter de navigation à préparer (cf. le
  # `render` surchargé de BaseController).
  def set_presenters; end
end
