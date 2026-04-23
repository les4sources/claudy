class GatheringCategoriesController < BaseController
  breadcrumb "Organisation", :root_path, match: :exact
  breadcrumb "Types de rassemblements", :gathering_categories_path, match: :exact

  def index
    @gathering_categories = GatheringCategory.ordered
  end

  def show
    @gathering_category = GatheringCategory.find_by!(id: params[:id])
  end

  def new
    @gathering_category = GatheringCategory.new
  end

  def create
    service = GatheringCategories::CreateService.new
    if service.run(params)
      redirect_to service.gathering_category,
                  notice: "La catégorie de rassemblement a été créée."
    else
      @gathering_category = service.gathering_category
      set_error_flash(service.gathering_category, service.error_message)
      render :new
    end
  end

  def edit
    @gathering_category = GatheringCategory.find_by!(id: params[:id])
  end

  def update
    service = GatheringCategories::UpdateService.new(
      gathering_category: GatheringCategory.find(params[:id])
    )
    if service.run(params)
      redirect_to gathering_category_path(service.gathering_category),
                  notice: "La catégorie de rassemblement a été mise à jour."
    else
      @gathering_category = service.gathering_category
      set_error_flash(service.gathering_category, service.error_message)
      render :edit,
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    @gathering_category = GatheringCategory.find_by!(id: params[:id])
    @gathering_category.soft_delete!(validate: false)
    redirect_to gathering_categories_url,
                status: :see_other,
                notice: "La catégorie de rassemblement a été supprimée."
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation",
      active_secondary: "gathering_categories"
    )
  end
end
