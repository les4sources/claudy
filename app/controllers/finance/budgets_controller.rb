module Finance
  # Comptabilité › États › Budget (étape 4 du redressement, Michael,
  # 2026-10-18). Une entité et une année à la fois ; l'année par défaut est la
  # prochaine, celle qu'on prépare.
  class BudgetsController < Finance::AccountingBaseController
    before_action :load_sheet

    breadcrumb "Budget", :finance_budget_path, match: :exact

    def show
      @entities = LegalEntity.actives.sort_by { |entity| [entity.form == "foundation" ? 0 : 1, entity.name] }
      @teams = Team.ordered.to_a
      @accounts = GeneralAccount.actives.where(klass: BudgetLine::CLASSES).ordered.to_a
    end

    # Toute la feuille d'un coup (`amounts`), ou une ligne ajoutée (`new_line`).
    def update
      amounts = params.fetch(:amounts, {}).permit!.to_h
      if (added = new_line_amount)
        amounts.merge!(added)
      end
      errors = @sheet.save(amounts)

      if errors.empty?
        redirect_to finance_budget_path(entity_id: @entity.id, year: @year), notice: "Budget #{@year} enregistré."
      else
        redirect_to finance_budget_path(entity_id: @entity.id, year: @year), alert: errors.to_sentence
      end
    end

    private

    def load_sheet
      @year = (params[:year].presence || Date.current.year + 1).to_i
      raise ActiveRecord::RecordNotFound unless (2000..2100).cover?(@year)

      @entity = params[:entity_id].present? ? LegalEntity.find(params[:entity_id]) : default_entity
      @sheet = Finance::BudgetSheet.new(legal_entity: @entity, year: @year)
    end

    def default_entity
      LegalEntity.actives.find_by(form: "foundation") || LegalEntity.actives.ordered.first!
    end

    def new_line_amount
      line = params[:new_line]
      return if line.blank? || line[:general_account_id].blank?

      { Finance::BudgetSheet.key_for(line[:team_id].presence&.to_i, line[:general_account_id].to_i) => line[:amount] }
    end
  end
end
