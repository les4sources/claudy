module Finance
  # Comptabilité > Caisse > Motifs (epic #243, phase 1). Le vocabulaire de la
  # feuille de caisse et son affectation comptable. L'ordre compte : c'est celui
  # de la liste de saisie, qu'on veut du plus fréquent au plus rare.
  #
  # On ne supprime pas un motif, on le désactive : des lignes de caisse passées
  # le portent, et une feuille du mois dernier doit rester lisible.
  class CashMotifsController < Finance::AccountingBaseController
    before_action :get_motif, only: %i[edit update move deactivate reactivate]

    breadcrumb "Motifs de caisse", :finance_cash_motifs_path, match: :exact

    def index
      @motifs = CashMotif.ordered.includes(:general_account, :team, :legal_entity)
    end

    def new
      @motif = CashMotif.new(position: CashMotif.next_position,
                             legal_entity: LegalEntity.actives.ordered.first)
    end

    def create
      @motif = CashMotif.new(motif_params)

      if @motif.save
        redirect_to finance_cash_motifs_path, notice: "Motif « #{@motif.label} » créé."
      else
        flash.now[:alert] = @motif.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @motif.update(motif_params)
        redirect_to finance_cash_motifs_path, notice: "Motif « #{@motif.label} » mis à jour."
      else
        flash.now[:alert] = @motif.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Échange la position avec le motif voisin — le geste minimal pour ranger
    # une liste, sans dépendance de glisser-déposer.
    def move
      neighbour = neighbour_for(params[:direction])

      if neighbour
        position = neighbour.position
        neighbour.update!(position: @motif.position)
        @motif.update!(position: position)
      end

      redirect_to finance_cash_motifs_path
    end

    def deactivate
      @motif.update(active: false)
      redirect_to finance_cash_motifs_path, notice: "Motif « #{@motif.label} » désactivé."
    end

    def reactivate
      @motif.update(active: true)
      redirect_to finance_cash_motifs_path, notice: "Motif « #{@motif.label} » réactivé."
    end

    private

    def get_motif = @motif = CashMotif.find(params[:id])

    def neighbour_for(direction)
      others = CashMotif.where.not(id: @motif.id)

      if direction == "up"
        others.where(position: ..@motif.position).order(position: :desc, id: :desc).first
      else
        others.where(position: @motif.position..).order(:position, :id).first
      end
    end

    def motif_params
      params.require(:cash_motif).permit(:label, :direction, :general_account_id,
                                         :team_id, :legal_entity_id, :position, :active)
    end

    def accounting_secondary = "cash_motifs"
  end
end
