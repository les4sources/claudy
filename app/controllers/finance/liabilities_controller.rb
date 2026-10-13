module Finance
  # Comptabilité > Fournisseurs > Dettes et litiges (2026-10-13).
  #
  # Ce que la maison doit ou risque de devoir sans facture encodée : la taxe
  # communale d'hébergement réclamée par Yvoir, un arriéré, une contestation.
  # Écrit une fois — réclamé, fourchette, retenu, date probable — pour que la
  # trésorerie le retire et que la situation ne paraisse pas meilleure qu'elle
  # n'est.
  class LiabilitiesController < Finance::AccountingBaseController
    before_action :get_liability, only: %i[edit update destroy]

    breadcrumb "Dettes et litiges", :finance_liabilities_path, match: :exact

    def index
      liabilities = Liability.ordered.includes(:legal_entity, :third_party, :team).to_a
      @open = liabilities.select(&:open?)
      @closed = liabilities.reject(&:open?)
      @by_entity = @open.group_by(&:legal_entity).sort_by { |entity, _| entity.name }
    end

    def new
      @liability = Liability.new(legal_entity: default_entity, kind: "dispute", installments: 1)
    end

    def create
      @liability = Liability.new(liability_params)
      apply_prudent_default(@liability)

      if @liability.save
        redirect_to finance_liabilities_path, notice: "« #{@liability.label} » enregistrée."
      else
        flash.now[:alert] = @liability.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      @liability.assign_attributes(liability_params)
      apply_prudent_default(@liability)

      if @liability.save
        redirect_to finance_liabilities_path, notice: "« #{@liability.label} » mise à jour."
      else
        flash.now[:alert] = @liability.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Une erreur d'encodage se supprime ; une dette payée ou un litige gagné se
    # SOLDE ou s'ABANDONNE (statut), pour garder la trace de ce qui a pesé.
    def destroy
      @liability.soft_delete!(validate: false)
      redirect_to finance_liabilities_path, notice: "« #{@liability.label} » supprimée."
    end

    private

    def get_liability = @liability = Liability.find(params[:id])

    def default_entity = LegalEntity.actives.find_by(form: "foundation")

    # Montant retenu laissé vide : le haut de la fourchette, sinon le réclamé.
    def apply_prudent_default(liability)
      return if liability.retained_cents.present?

      liability.retained_cents = Liability.prudent_retained_cents(claimed_cents: liability.claimed_cents,
                                                                  high_cents: liability.high_cents)
    end

    def liability_params
      params.require(:liability).permit(:legal_entity_id, :third_party_id, :team_id, :general_account_id, :label,
                                        :kind, :claimed, :low, :high, :retained, :paid, :expected_on,
                                        :installments, :status, :closed_on, :notes)
    end

    def accounting_secondary = "liabilities"
  end
end
