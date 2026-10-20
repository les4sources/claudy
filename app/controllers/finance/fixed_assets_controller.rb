module Finance
  # Comptabilité › États › Immobilisations (revue expert-comptable du
  # 2026-10-20) : le registre des biens amortis, et les dotations d'un exercice
  # passées d'un geste.
  class FixedAssetsController < Finance::AccountingBaseController
    before_action :get_asset, only: %i[edit update destroy]
    breadcrumb "Immobilisations", :finance_fixed_assets_path, match: :exact

    def index
      @entities = LegalEntity.actives.sort_by { |entity| [entity.form == "foundation" ? 0 : 1, entity.name] }
      @entity = LegalEntity.find_by(id: params[:legal_entity_id]) || @entities.first
      @years = @entity ? @entity.fiscal_years.sort_by(&:starts_on).reverse : []
      @year = @years.find { |year| year.id == params[:fiscal_year_id].to_i } || @years.find { |year| year.covers?(Date.current) } || @years.first
      @assets = FixedAsset.where(legal_entity: @entity).includes(:general_account, :depreciation_account, :team, depreciations: :fiscal_year).ordered.to_a
      @posting = @year && Accounting::PostDepreciations.new(fiscal_year: @year)
      @ledger_check = ledger_check if @year
    end

    def new
      @asset = FixedAsset.new(legal_entity_id: params[:legal_entity_id], useful_life_years: 5,
                              expense_account: GeneralAccount.find_by(code: FixedAsset::DEFAULT_EXPENSE_CODE))
    end

    def create
      @asset = FixedAsset.new(asset_params)
      if @asset.save
        redirect_to finance_fixed_assets_path(legal_entity_id: @asset.legal_entity_id), notice: "Immobilisation « #{@asset.name} » ajoutée au registre."
      else
        flash.now[:alert] = @asset.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @asset.update(asset_params)
        redirect_to finance_fixed_assets_path(legal_entity_id: @asset.legal_entity_id), notice: "Immobilisation mise à jour."
      else
        flash.now[:alert] = @asset.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Un bien déjà doté ne se retire pas du registre : ses dotations sont au
    # grand livre. Il se marque « sorti » à la place.
    def destroy
      if @asset.depreciations.exists?
        redirect_to finance_fixed_assets_path(legal_entity_id: @asset.legal_entity_id),
                    alert: "Ce bien a des dotations au grand livre : indique plutôt sa date de sortie."
      else
        @asset.destroy
        redirect_to finance_fixed_assets_path(legal_entity_id: @asset.legal_entity_id), notice: "Immobilisation retirée du registre."
      end
    end

    def depreciate
      year = FiscalYear.find(params.require(:fiscal_year_id))
      rows = Accounting::PostDepreciations.new(fiscal_year: year, whodunnit: current_user&.email).run!
      redirect_to finance_fixed_assets_path(legal_entity_id: year.legal_entity_id, fiscal_year_id: year.id),
                  notice: "#{rows.size} dotation(s) passée(s) au #{l(year.ends_on)} : " \
                          "#{helpers.humanized_money_with_symbol(Money.new(rows.sum(&:amount_cents), 'EUR'))}."
    rescue ServiceError => e
      redirect_to finance_fixed_assets_path(legal_entity_id: year&.legal_entity_id, fiscal_year_id: year&.id), alert: e.message
    end

    def cancel_depreciation
      depreciation = FixedAssetDepreciation.find(params[:id])
      year = depreciation.fiscal_year
      Accounting::CancelDepreciation.new(depreciation: depreciation, whodunnit: current_user&.email).run!
      redirect_to finance_fixed_assets_path(legal_entity_id: year.legal_entity_id, fiscal_year_id: year.id),
                  notice: "Dotation #{year.label} de « #{depreciation.fixed_asset.name} » contre-passée."
    rescue ServiceError => e
      redirect_to finance_fixed_assets_path(legal_entity_id: year.legal_entity_id, fiscal_year_id: year.id), alert: e.message
    end

    private

    def get_asset = @asset = FixedAsset.find(params[:id])

    def asset_params
      params.require(:fixed_asset).permit(:legal_entity_id, :name, :general_account_id, :depreciation_account_id,
                                          :expense_account_id, :team_id, :acquired_on, :acquisition, :useful_life_years,
                                          :prior_depreciation, :disposed_on, :notes)
    end

    # Le registre face au grand livre, compte par compte, à la fin de
    # l'exercice : ce que le registre explique du solde des comptes de classe 2
    # qu'il utilise. Un écart, c'est un bien acheté mais pas inscrit (ou
    # l'inverse).
    def ledger_check
      sums = Accounting::Balances.new(@entity).through(@year.ends_on)
      in_service = @assets.reject { |asset| asset.acquired_on > @year.ends_on || (asset.disposed_on && asset.disposed_on <= @year.ends_on) }
      accounts = (in_service.map(&:general_account) + in_service.map(&:depreciation_account)).uniq.sort_by(&:code)
      accounts.map do |account|
        registry = in_service.sum do |asset|
          value = asset.general_account_id == account.id ? asset.acquisition_cents : 0
          if asset.depreciation_account_id == account.id
            value -= asset.prior_depreciation_cents +
                     asset.depreciations.select { |d| d.fiscal_year.starts_on <= @year.starts_on }.sum(&:amount_cents)
          end
          value
        end
        { account: account, registry_cents: registry, ledger_cents: sums[account.id] }
      end
    end
  end
end
