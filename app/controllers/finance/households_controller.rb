module Finance
  # CRUD minimal des ménages (issue #155). Les membres se saisissent en même
  # temps que le ménage : c'est leur période de présence qui fera foi quand on
  # recalculera « 10 €/adulte » pour un mois passé.
  class HouseholdsController < Finance::BaseController
    before_action :get_household, only: [:show, :edit, :update, :destroy]

    breadcrumb "Ménages", :finance_households_path, match: :exact

    def index
      @households = Household.ordered.includes(:household_members)
    end

    def show
      breadcrumb @household.name, finance_household_path(@household), match: :exact

      @members = @household.household_members.ordered
      @accounts = MemberAccountDecorator.decorate_collection(@household.member_accounts.ordered)
    end

    def new
      @household = Household.new(kind: "resident", moved_in_on: Date.current)
      blank_members(@household)
    end

    def create
      @household = Household.new(household_params)

      if @household.save
        redirect_to finance_household_path(@household),
                    notice: "Le ménage « #{@household.name} » a été créé."
      else
        flash.now[:alert] = @household.errors.full_messages.to_sentence
        blank_members(@household)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      blank_members(@household)
    end

    def update
      if @household.update(household_params)
        redirect_to finance_household_path(@household), notice: "Le ménage a été mis à jour."
      else
        flash.now[:alert] = @household.errors.full_messages.to_sentence
        blank_members(@household)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @household.member_accounts.exists?
        redirect_to finance_household_path(@household),
                    alert: "Ce ménage porte encore un compte : supprime d'abord le compte."
      else
        @household.soft_delete!(validate: false)
        redirect_to finance_households_path, notice: "Le ménage « #{@household.name} » a été supprimé."
      end
    end

    private

    def get_household
      @household = Household.find(params[:id])
    end

    # UNE ligne vierge pour démarrer ; les suivantes s'ajoutent au clic, sans
    # limite (contrôleur Stimulus `nested_form`). Avant, trois lignes fixes
    # plafonnaient la saisie à trois personnes par passage — or il y a des
    # ménages de cinq. Les lignes laissées vides restent ignorées (`reject_if`
    # sur le nom).
    def blank_members(household)
      household.household_members.build(kind: "adult", started_on: household.moved_in_on || Date.current)
    end

    def household_params
      params.require(:household).permit(
        :name, :kind, :moved_in_on, :moved_out_on, :notes,
        household_members_attributes: [:id, :name, :kind, :human_id, :born_on, :started_on, :ended_on, :_destroy]
      )
    end

    def finance_secondary = "households"
  end
end
