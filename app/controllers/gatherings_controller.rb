class GatheringsController < BaseController
  before_action :get_gathering, only: [:show, :edit, :update, :destroy]

  breadcrumb "Organisation", :root_path, match: :exact
  breadcrumb "Rassemblements", :gatherings_path, match: :exact

  def index
    @gatherings = GatheringDecorator.decorate_collection(
      Gathering.all.includes(:gathering_category).order(starts_at: :desc)
    )
  end

  def show
    @gathering = GatheringDecorator.new(@gathering)
  end

  def new
    @gathering = Gathering.new
  end

  def create
    service = Gatherings::CreateService.new
    if service.run(params)
      redirect_to gathering_path(service.gathering),
                  notice: "Le rassemblement a été ajouté."
    else
      @gathering = service.gathering
      set_error_flash(service.gathering, service.error_message)
      render :new
    end
  end

  def edit
    @gathering.starts_at_date = @gathering.starts_at.to_date
    @gathering.ends_at_date = @gathering.ends_at.to_date
    @gathering.starts_at_time = @gathering.starts_at.to_time
    @gathering.ends_at_time = @gathering.ends_at.to_time
  end

  def update
    service = Gatherings::UpdateService.new(
      gathering: Gathering.find(params[:id])
    )
    if service.run(params)
      redirect_to gathering_path(service.gathering),
                  notice: "Le rassemblement a été mis à jour."
    else
      @gathering = service.gathering
      set_error_flash(service.gathering, service.error_message)
      render :edit,
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    if @gathering.soft_delete!(validate: false)
      redirect_to gatherings_path,
                  notice: "Le rassemblement a été supprimé."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  def quick_create
    category = GatheringCategory.find(params[:category_id])
    date = Date.parse(params[:date])
    gathering = build_from_category(category, date)
    gathering.save!

    if category.variable_time?
      redirect_to edit_gathering_path(gathering),
                  notice: "Précisez les horaires de ce rassemblement."
    else
      respond_to do |format|
        format.turbo_stream do
          @gathering = GatheringDecorator.new(gathering)
          @date = date
        end
        format.html { redirect_to root_path(view: "organisation", start_date: date.iso8601) }
      end
    end
  end

  private

  def get_gathering
    @gathering = Gathering.find(params[:id])
  end

  def build_from_category(category, date)
    start_offset_seconds =
      if category.default_start_time.present?
        category.default_start_time.seconds_since_midnight.to_i
      else
        12 * 3600
      end
    duration_minutes = category.default_duration_minutes || 60

    starts_at = date.in_time_zone.beginning_of_day + start_offset_seconds.seconds
    ends_at = starts_at + duration_minutes.minutes

    Gathering.new(
      gathering_category: category,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation",
      active_secondary: "gatherings"
    )
  end
end
