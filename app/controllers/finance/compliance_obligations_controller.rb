module Finance
  # Les règles de l'échéancier comptable. Enregistrer une règle génère tout de
  # suite ses échéances : on voit ce qu'on vient de décrire, pas une promesse
  # que la tâche de nuit tiendra peut-être.
  class ComplianceObligationsController < AccountingBaseController
    before_action :get_obligation, only: %i[edit update]

    breadcrumb "Échéancier", :finance_compliance_deadlines_path
    breadcrumb "Obligations", :finance_compliance_obligations_path, match: :exact

    def index
      @obligations = ComplianceObligation.includes(:legal_entity, :responsible_user).ordered
                                         .sort_by { |obligation| [obligation.legal_entity.name, obligation.active? ? 0 : 1, obligation.title] }
      @next_deadlines = ComplianceDeadline.outstanding.ordered.group_by(&:compliance_obligation_id).transform_values(&:first)
    end

    def new
      @obligation = ComplianceObligation.new(frequency: "yearly", covers: "previous", active: true,
                                             first_due_on: Date.current, responsible_user: current_user)
    end

    def create
      @obligation = ComplianceObligation.new(obligation_params)

      if @obligation.save
        report = generate(@obligation)
        redirect_to finance_compliance_obligations_path, notice: "« #{@obligation.title} » est enregistrée — #{report}."
      else
        flash.now[:alert] = @obligation.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @obligation.update(obligation_params)
        report = generate(@obligation)
        redirect_to finance_compliance_obligations_path, notice: "« #{@obligation.title} » est mise à jour — #{report}."
      else
        flash.now[:alert] = @obligation.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def get_obligation
      @obligation = ComplianceObligation.find(params[:id])
    end

    def generate(obligation)
      ComplianceDeadlines::Generate.new(obligations: ComplianceObligation.where(id: obligation.id)).run!
    end

    def obligation_params
      params.require(:compliance_obligation).permit(:title, :legal_entity_id, :frequency, :first_due_on, :ends_on,
                                                    :covers, :payment, :responsible_user_id, :instructions, :active)
    end

    def accounting_secondary = "deadlines"
  end
end
