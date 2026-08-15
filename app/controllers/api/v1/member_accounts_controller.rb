module Api
  module V1
    # Comptes courants internes (#155, création ouverte en #193).
    #
    # Ce que l'API sert d'abord, c'est la correspondance « nom de famille →
    # compte », dont un encodage de fiche papier a besoin avant d'écrire quoi que
    # ce soit. La reprise de l'historique y a ajouté la création : les fiches de
    # bar d'avant 2025 portent des colonnes — ménages partis, personnes de
    # passage — qui n'ont aucun compte dans claudy. Sans compte, leur
    # consommation est perdue et aucun total mensuel ne se recoupe.
    #
    # POST est un UPSERT sur le NOM, pour la même raison que sur le catalogue :
    # deux comptes « Feyens » rendraient tout recoupement impossible, et un
    # import rejoué après une coupure ne doit pas en fabriquer un second.
    #
    # Le solde n'est jamais stocké : il est recalculé pour toute la page en une
    # requête groupée (MemberAccounts::Summary), pas une par compte.
    class MemberAccountsController < BaseController
      before_action :get_account, only: [:show, :update]

      def index
        scope = MemberAccount.ordered
        scope = scope.where("member_accounts.name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
        scope = scope.where(kind: params[:kind]) if params[:kind].present?

        active = ActiveModel::Type::Boolean.new.cast(params[:active])
        scope = active ? scope.actives : scope.inactives unless active.nil?

        @member_accounts = paginate(scope)
        MemberAccounts::Summary.new(@member_accounts).accounts
      end

      def show; end

      # Le ménage (ou la personne) créé à la volée et le compte lui-même vivent
      # ou tombent ensemble : sans transaction, un compte refusé en validation
      # laisserait derrière lui un ménage orphelin que la requête suivante
      # retrouverait, et l'erreur deviendrait invisible.
      def create
        saved = false

        MemberAccount.transaction do
          attributes = account_params.merge(resolve_anchor)
          @member_account = MemberAccount.find_or_initialize_by(name: attributes[:name])
          @created = @member_account.new_record?

          saved = @member_account.update(attributes)
          raise ActiveRecord::Rollback unless saved
        end

        return render_invalid(@member_account) unless saved

        render :show, status: @created ? :created : :ok
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record)
      end

      def update
        if @member_account.update(account_params)
          render :show
        else
          render_invalid(@member_account)
        end
      end

      private

      def get_account
        @member_account = MemberAccount.find(params[:id])
      end

      # Un compte de ménage EXIGE un ménage, un compte de personne EXIGE une
      # personne (contrainte du modèle, tenue aussi en base). Or l'API ne sait
      # créer ni l'un ni l'autre, et les fiches de bar d'avant 2025 portent des
      # ménages partis qui n'existent nulle part dans claudy. On accepte donc de
      # les créer ICI, à la volée, sur leur nom — sinon la création de compte est
      # un endpoint qui ne peut servir qu'aux ménages déjà connus, c'est-à-dire à
      # ceux qui ont déjà un compte.
      def resolve_anchor
        source = params.require(:member_account)
        anchor = {}

        if source[:household].present?
          attrs = source.require(:household).permit(:name, :kind, :moved_in_on, :moved_out_on, :notes)
          household = Household.find_or_initialize_by(name: attrs[:name])
          household.update!(attrs.to_h.compact_blank.reverse_merge(kind: "resident"))
          anchor[:household_id] = household.id
        end

        if source[:human].present?
          attrs = source.require(:human).permit(:name, :email)
          # `Human` porte `default_scope { where(status: "active") }`. Chercher
          # sans le lever ne verrait pas une personne partie et en créerait un
          # doublon — exactement le genre de doublon qui fait diverger deux
          # comptes courants pour la même personne.
          human = Human.unscope(where: :status).find_or_initialize_by(name: attrs[:name])
          human.update!(attrs.to_h.compact_blank)
          anchor[:human_id] = human.id
        end

        anchor
      end

      def account_params
        params.require(:member_account).permit(:name, :kind, :contact_email, :active,
                                               :opening_balance_cents, :opening_balance_on,
                                               :household_id, :human_id)
      end
    end
  end
end
