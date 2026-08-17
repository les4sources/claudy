module Api
  module V1
    # Écritures de compte courant (#193).
    #
    # Les fiches papier ont leur propre chemin d'écriture (`/paper_sheets/:id/encode`),
    # parce qu'une fiche est une MATRICE et qu'on l'encode d'un bloc. Tout le
    # reste du grand livre — charges habitants, loyer, pension, location du dôme,
    # forfaits, arrondis de reprise — est une écriture isolée, datée, libellée :
    # c'est ce que cet endpoint écrit.
    #
    # `idempotency_key` porte toute la sûreté de la reprise. Avec une clé, POST
    # est un UPSERT : rejouer un import après une coupure met à jour l'écriture
    # au lieu d'en créer une seconde. Sans clé, la création reste possible mais
    # n'est pas rejouable — et une reprise d'historique de quatre ans qui n'est
    # pas rejouable n'a aucune chance d'aboutir.
    #
    # Une écriture rattachée à un décompte émis est VERROUILLÉE : elle sort en
    # 409 plutôt que d'être modifiée en silence. Le modèle refuserait de toute
    # façon (`AccountEntry::Locked`), mais un 500 ne dit pas à l'appelant ce
    # qu'il doit faire — une contre-écriture.
    class AccountEntriesController < BaseController
      def index
        scope = AccountEntry.chronological.includes(:member_account)
        scope = scope.where(member_account_id: params[:member_account_id]) if params[:member_account_id].present?
        scope = scope.where(flow: params[:flow]) if params[:flow].present?
        scope = scope.where(source: params[:source]) if params[:source].present?
        scope = scope.where("entry_date >= ?", params[:from]) if params[:from].present?
        scope = scope.where("entry_date <= ?", params[:to]) if params[:to].present?

        @account_entries = paginate(scope)
      end

      def show
        @account_entry = AccountEntry.find(params[:id])
      end

      def create
        attributes = entry_params
        key = attributes[:idempotency_key].presence

        existing = key && AccountEntry.find_by(idempotency_key: key)
        return render_locked(existing) if existing&.locked?

        @account_entry = existing || AccountEntry.new
        @created = @account_entry.new_record?

        if @account_entry.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@account_entry)
        end
      # Le décompte a pu être émis ENTRE le contrôle et l'écriture. Le modèle
      # refuse alors, et l'appelant doit recevoir le même 409 exploitable qu'au
      # premier contrôle, pas une 500 sans mode d'emploi.
      rescue AccountEntry::Locked
        render_locked(@account_entry.reload)
      end

      private

      def render_locked(entry)
        render json: {
          error: "conflict",
          message: "Écriture ##{entry.id} rattachée à un décompte émis : elle ne peut plus être modifiée. " \
                   "La correction passe par une contre-écriture.",
          account_entry_id: entry.id,
          account_statement_id: entry.account_statement_id
        }, status: :conflict
      end

      def entry_params
        params.require(:account_entry).permit(:member_account_id, :entry_date, :posted_at,
                                              :amount_cents, :flow, :kind, :label, :source,
                                              :idempotency_key, :quantity, :unit_price_cents,
                                              :price_basis, :catalog_item_id)
      end
    end
  end
end
