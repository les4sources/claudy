class StaysController < BaseController
  before_action :set_accounting_view

  # Rendu sans layout : le fragment HTML est injecté dans la modale de détails
  # par le contrôleur Stimulus stay-details (fetch + innerHTML).
  def show
    @stay = Stay.includes(stay_items: :bookable, customer: []).find(params[:id]).decorate
    render layout: false
  end

  private

  def set_accounting_view
    @accounting_view = true
  end

  def set_presenters; end
end
