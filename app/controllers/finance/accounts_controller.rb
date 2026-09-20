module Finance
  # Liste des comptes courants et grand livre d'un compte (issue #155).
  class AccountsController < Finance::BaseController
    FILTERS = %w[active inactive all].freeze

    before_action :get_account, only: [:show, :retrospective, :poste, :edit, :update, :destroy]

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
      # `settlement` préchargé : la table affiche la communication de chaque
      # virement, et sans ça c'est une requête par ligne de règlement.
      @groupes = MemberAccounts::GroupedLedger.new(
        @account.account_entries.recent_first.includes(:settlement)
      ).groupes
      @entry = @account.account_entries.new(entry_date: Date.current)
      @account = MemberAccountDecorator.new(@account)
    end

    # Le détail d'un poste encore dû (Michael, 2026-09-20). « Bar 273,09 € »
    # répond à « combien », pas à « quoi » — et c'est « quoi » qu'on vient
    # vérifier quand un montant surprend. Le calcul est le MÊME service que
    # celui du bloc « À régler » : deux chemins de calcul finiraient par
    # afficher deux vérités.
    def poste
      @poste = MemberAccounts::Outstanding.new(@account).poste(params[:flow])

      return redirect_to finance_account_path(@account), alert: "Ce poste n'a plus rien à régler." if @poste.nil?

      @account = MemberAccountDecorator.new(@account)
      # Le layout `modal`, pas celui de l'application : ce dernier porte déjà un
      # `turbo_frame_tag "modal"` vide, et Turbo retient le PREMIER cadre du même
      # identifiant qu'il trouve dans la réponse — la fenêtre restait blanche.
      # Il se pose ICI et pas en `layout ... only:` : une condition non remplie
      # laisse Rails SANS layout du tout au lieu de retomber sur celui du parent,
      # et toutes les autres actions du contrôleur perdaient leur navigation.
      # Hors requête de cadre, ce layout rend une page autonome — l'URL d'un
      # poste reste partageable.
      render layout: "modal"
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
