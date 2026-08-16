module Api
  module V1
    # Les lignes du journal de trésorerie, hors CODA (#200).
    #
    # Jusqu'ici, la seule façon d'écrire une ligne par l'API était de déposer un
    # fichier CODA. Une caisse en ESPÈCES n'en produit pas, et les feuilles de
    # caisse du domaine couvrent cinquante mois depuis janvier 2022 : il fallait
    # un chemin d'écriture pour ce que la banque ne raconte pas.
    #
    # `external_ref` porte l'idempotence, et la base la garantit : un index
    # unique sur (compte, référence) tranche même en concurrence. Rejouer un
    # import met donc à jour la ligne au lieu d'en créer une seconde.
    #
    # Une ligne déjà COMPTABILISÉE ne bouge plus — le modèle la gèle, et l'API
    # rend un 409 qui dit quoi faire plutôt qu'une 500 qui ne dit rien.
    class CashEntriesController < BaseController
      def index
        scope = CashEntry.order(:entry_date, :id).includes(:cash_account)
        scope = scope.where(cash_account_id: params[:cash_account_id]) if params[:cash_account_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where("entry_date >= ?", params[:from]) if params[:from].present?
        scope = scope.where("entry_date <= ?", params[:to]) if params[:to].present?

        @cash_entries = paginate(scope)
      end

      def show
        @cash_entry = CashEntry.find(params[:id])
      end

      def create
        attributes = entry_params.merge(resolve_account)
        return if performed?

        reference = attributes[:external_ref].presence
        existing = reference && CashEntry.find_by(cash_account_id: attributes[:cash_account_id],
                                                 external_ref: reference)
        return render_posted(existing) if existing&.posted?

        @cash_entry = existing || CashEntry.new
        @created = @cash_entry.new_record?

        if @cash_entry.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@cash_entry)
        end
      end

      private

      # Une reprise connaît « Caisse du bar », pas un identifiant technique :
      # l'un ou l'autre suffit, et un nom inconnu est refusé plutôt que de créer
      # un compte de trésorerie à la volée.
      def resolve_account
        source = params.require(:cash_entry)
        return {} if source[:cash_account_name].blank?

        account = CashAccount.find_by(name: source[:cash_account_name])
        if account.nil?
          render json: { error: "unprocessable_entity",
                         message: "Compte de trésorerie inconnu : #{source[:cash_account_name]}." },
                 status: :unprocessable_entity
          return {}
        end

        { cash_account_id: account.id }
      end

      def render_posted(entry)
        render json: {
          error: "conflict",
          message: "Ligne ##{entry.id} déjà comptabilisée : elle est gelée. " \
                   "La correction passe par une contre-passation de son écriture.",
          cash_entry_id: entry.id
        }, status: :conflict
      end

      def entry_params
        params.require(:cash_entry).permit(:cash_account_id, :entry_date, :value_date, :amount_cents,
                                           :label, :counterparty_name, :counterparty_iban,
                                           :communication, :external_ref, :statement_ref,
                                           :transaction_code)
      end
    end
  end
end
