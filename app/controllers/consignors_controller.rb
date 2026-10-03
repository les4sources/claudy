# Paramètres > Dépôt-vente (epic #248, phase 1) : le carnet des artisans qui
# déposent des produits à l'épicerie. Pas de destruction — on désactive, pour
# que les relevés passés (phase 2) gardent leur artisan.
class ConsignorsController < BaseController
  before_action :get_consignor, only: %i[edit update deactivate reactivate sheet]
  before_action :load_humans,   only: %i[new create edit update]

  breadcrumb "Dépôt-vente", :consignors_path, match: :exact

  def index
    @consignors = Consignor.ordered
  end

  def new
    @consignor = Consignor.new(settlement_mode: "transfer",
                               commission_percent: Consignor.column_defaults["commission_percent"],
                               starts_on: Date.current)
  end

  def create
    @consignor = Consignor.new(consignor_params)

    if @consignor.save
      seed_allocation_rule
      redirect_to consignors_path, notice: "L'artisan « #{@consignor.name} » a été ajouté."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    breadcrumb @consignor.name, edit_consignor_path(@consignor)
  end

  # Sa feuille du carnet Artisanat (epic #359, phase 3), imprimée depuis
  # l'admin pour un artisan qui ne passe pas par son espace.
  def sheet
    @qr = Shop::EpcQrCode.new(communication: @consignor.sheet_communication)
    @printed_on = Date.current
    @number = @consignor.next_sheet_number! if @qr.configured?
    render "shop/sheets/consignor", layout: "print_sheet"
  end

  def update
    if @consignor.update(consignor_params)
      seed_allocation_rule
      redirect_to consignors_path, notice: "L'artisan « #{@consignor.name} » a été mis à jour."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def deactivate
    @consignor.update(active: false)
    redirect_to consignors_path, notice: "Le contrat de « #{@consignor.name} » est désactivé."
  end

  def reactivate
    @consignor.update(active: true)
    redirect_to consignors_path, notice: "Le contrat de « #{@consignor.name} » est réactivé."
  end

  private

  # Un artisan avec accès à l'espace a sa règle « ARTISANAT <PRÉNOM> » (epic
  # #359, phase 4) : ses virements se proposent d'eux-mêmes au rapprochement.
  # Idempotent — à la modification, rien ne bouge si la règle existe déjà.
  def seed_allocation_rule
    return unless @consignor.active? && @consignor.portal_enabled?

    Shop::SeedAllocationRules.new.for_consignor(@consignor)
  end

  def get_consignor
    @consignor = Consignor.find(params[:id])
  end

  # Le sélecteur « membre de l'équipe » ne sert qu'à pré-remplir : il liste les
  # humains actifs, plus celui déjà lié s'il a depuis été désactivé.
  def load_humans
    @humans = Human.order(:name).to_a
    @humans |= [@consignor.human].compact if @consignor
  end

  # `iban` vide ne doit pas écraser un IBAN existant par une chaîne vide quand
  # le mode passe à `invoice` : la validation de présence ne vaut qu'en
  # `transfer`, donc on laisse passer — l'IBAN reste disponible si l'artisan
  # repasse au virement.
  def consignor_params
    params.require(:consignor).permit(:name, :email, :human_id, :third_party_id,
                                      :commission_percent, :settlement_mode, :iban,
                                      :starts_on, :ends_on, :active, :notes,
                                      :portal_enabled)
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "consignors"
    )
    @settings_view = true
  end
end
