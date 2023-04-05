class LodgingsController < BaseController
  include HttpAuthConcern
  
  def index
    @lodgings = Lodging.all
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "lodgings",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end
end
