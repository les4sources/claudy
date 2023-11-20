class HumanRolesController < BaseController
  def create
    @human_role = HumanRole.create(human_role_params)
    @human_roles = HumanRole.where(date: @human_role.date)
  end

  def destroy
    @human_role = HumanRole.find(params[:id])
    date = @human_role.date
    
    if @human_role
      @human_role.destroy
      @human_roles = HumanRole.where(date: date)
    end
  end

  private

  def human_role_params
    params.permit(:human_id, :role_id, :date)
  end

  def set_presenters; end
end
