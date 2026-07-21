# Admin des packs de coworking (epic #126, Phase 1).
#
# L'équipe achète un pack pour un client existant, puis pose ou annule ses
# journées. Elle n'est PAS soumise aux règles du portail client (pas de limite
# d'heure) : seules les règles de domaine (capacité 3, lun-ven, expiration,
# crédits) s'appliquent.
class CoworkingPacksController < BaseController
  before_action :get_pack, only: [:show, :destroy]

  breadcrumb "Coworking", :coworking_packs_path, match: :exact

  def index
    @packs = CoworkingPack.includes(:customer, :payments, :coworking_reservations).ordered
  end

  def show
    breadcrumb @pack.customer.display_name, coworking_pack_path(@pack)
    @reservations = @pack.coworking_reservations.ordered
    @reservation = CoworkingReservation.new(coworking_pack: @pack)
  end

  def new
    @pack = CoworkingPack.new
  end

  def create
    service = Coworking::CreatePack.new
    if service.run(customer_id: pack_params[:customer_id],
                   days_total: pack_params[:days_total],
                   payment_method: pack_params[:payment_method])
      redirect_to coworking_pack_path(service.pack),
                  notice: "Le pack de #{service.pack.days_total} journée(s) a été créé."
    else
      @pack = service.pack
      flash.now[:alert] = service.error_message
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @pack.soft_delete!(validate: false)
    redirect_to coworking_packs_path, notice: "Le pack a été supprimé."
  end

  private

  def get_pack
    @pack = CoworkingPack.find(params[:id])
  end

  def pack_params
    params.require(:coworking_pack).permit(:customer_id, :days_total, :payment_method)
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "coworking"
    )
    @settings_view = true
  end
end
