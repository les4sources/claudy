module Finance
  # Les règles d'affectation (issue #183). Elles proposent, elles ne décident
  # jamais — et le compteur d'acceptations / refus de chaque règle est là pour
  # qu'on puisse juger, dans six mois, si elle mérite encore d'exister.
  class AllocationRulesController < Finance::AccountingBaseController
    before_action :get_rule, only: [:edit, :update, :destroy, :move]
    breadcrumb "Règles d'affectation", :finance_allocation_rules_path, match: :exact

    def index
      @rules = AllocationRule.ordered.includes(:general_account, :team, :legal_entity)
      @pending_suggestions = AllocationSuggestion.pending.count
    end

    def new
      @rule = AllocationRule.new(confidence: 80, position: (AllocationRule.maximum(:position) || 0) + 1)
    end

    def create
      @rule = AllocationRule.new(rule_params)

      if @rule.save
        Finance::SuggestAllocations.new.run!
        redirect_to finance_allocation_rules_path, notice: "Règle « #{@rule.label} » créée — les suggestions ont été recalculées."
      else
        flash.now[:alert] = @rule.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @rule.update(rule_params)
        redirect_to finance_allocation_rules_path, notice: "Règle mise à jour."
      else
        flash.now[:alert] = @rule.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # L'ordre est signifiant : la première règle qui matche gagne, ce qui permet
    # de poser une règle très spécifique avant une règle générale.
    def move
      direction = params[:direction] == "up" ? -1 : 1
      voisine = AllocationRule.ordered.where.not(id: @rule.id)
                              .send(direction.negative? ? :where : :where,
                                    direction.negative? ? ["position <= ?", @rule.position] : ["position >= ?", @rule.position])
      voisine = direction.negative? ? voisine.order(position: :desc).first : voisine.order(:position).first

      if voisine
        position = voisine.position
        voisine.update!(position: @rule.position)
        @rule.update!(position: position)
      end

      redirect_to finance_allocation_rules_path
    end

    def destroy
      @rule.destroy
      redirect_to finance_allocation_rules_path, notice: "Règle supprimée."
    end

    private

    def get_rule = @rule = AllocationRule.find(params[:id])

    def rule_params
      permitted = params.require(:allocation_rule).permit(
        :label, :position, :active, :counterparty_iban, :counterparty_name_contains,
        :communication_contains, :transaction_code, :direction, :confidence,
        :general_account_id, :analytic_account_id, :team_id, :legal_entity_id,
        :min_amount, :max_amount
      )
      %w[min max].each do |borne|
        valeur = permitted.delete(:"#{borne}_amount")
        permitted[:"#{borne}_amount_cents"] = valeur.present? ? Monetize.parse(valeur.to_s).cents : nil
      end
      permitted
    end
  end
end
