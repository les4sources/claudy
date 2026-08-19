module Finance
  # Liste des comptes courants et grand livre d'un compte (issue #155).
  class AccountsController < Finance::BaseController
    FILTERS = %w[active inactive all].freeze

    before_action :get_account, only: [:show, :retrospective, :edit, :update, :destroy]

    breadcrumb "Comptes", :finance_accounts_path, match: :exact

    def index
      @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "active"
      @accounts = MemberAccountDecorator.decorate_collection(
        MemberAccounts::Summary.new(filtered_scope).accounts
      )
    end

    def show
      breadcrumb @account.name, finance_account_path(@account), match: :exact

      @outstanding = MemberAccounts::Outstanding.new(@account)
      # Le grand livre est REPLIÉ par mois et par canal : cinq cents lignes de
      # bar déroulées une par une ne se lisent pas.
      @groupes = MemberAccounts::GroupedLedger.new(@account.account_entries.recent_first).groupes
      @entry = @account.account_entries.new(entry_date: Date.current)
      @account = MemberAccountDecorator.new(@account)
    end

    # La lecture agrégée d'un compte : le rythme, la répartition, ce qui revient
    # le plus. `periode` vient de l'URL et se valide dans le service — une URL
    # bricolée retombe sur la fenêtre glissante, elle ne rend pas une 500.
    def retrospective
      breadcrumb @account.name, finance_account_path(@account), match: :exact
      breadcrumb "Lecture du compte", retrospective_finance_account_path(@account), match: :exact

      @retrospective = MemberAccounts::Retrospective.new(@account, periode: params[:periode])
    end

    def new
      @account = MemberAccount.new(kind: "household", active: true)
    end

    def create
      @account = MemberAccount.new(account_params)

      if @account.save
        redirect_to finance_account_path(@account),
                    notice: "Le compte « #{@account.name} » a été créé (#{@account.code})."
      else
        flash.now[:alert] = @account.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @account.update(account_params)
        redirect_to finance_account_path(@account), notice: "Le compte a été mis à jour."
      else
        flash.now[:alert] = @account.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @account.soft_delete!(validate: false)
      redirect_to finance_accounts_path, notice: "Le compte « #{@account.name} » a été supprimé."
    end

    private

    def get_account
      @account = MemberAccount.find(params[:id])
    end

    def filtered_scope
      case @filter
      when "inactive" then MemberAccount.inactives.ordered
      when "all"      then MemberAccount.ordered
      else                 MemberAccount.actives.ordered
      end
    end

    # `code` n'est PAS éditable : la séquence n'est jamais réattribuée.
    #
    # L'ancre qui ne correspond pas au type est remise à zéro ici : changer un
    # compte de « ménage » à « entité » ne doit pas buter sur la contrainte CHECK
    # à cause d'un `household_id` resté dans le formulaire.
    def account_params
      attrs = params.require(:member_account).permit(
        :kind, :household_id, :human_id, :name, :contact_email,
        :opening_balance_on, :active
      )

      attrs[:human_id] = nil unless attrs[:kind] == "human"
      attrs[:household_id] = nil unless attrs[:kind] == "household"
      attrs.merge(opening_balance_cents: submitted_opening_balance_cents)
    end

    # Saisi en euros (virgule tolérée), stocké en cents. Vide = 0.
    def submitted_opening_balance_cents
      raw = params.dig(:member_account, :opening_balance_euros).to_s.strip.tr(",", ".")
      return 0 unless raw.match?(/\A-?\d+(\.\d+)?\z/)

      (raw.to_f * 100).round
    end
  end
end
