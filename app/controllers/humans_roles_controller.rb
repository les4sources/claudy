class HumansRolesController < BaseController
  def create
    @human_role = HumanRole.create(human_role_params)
    @human_roles = HumanRole.where(date: @human_role.date)
    render turbo_stream: 
      turbo_stream.replace("human-role-#{@human_role.date.iso8601}-#{@human_role.human_id}-#{@human_role.role_id}",
                          partial: "humans_roles/human_role",
                          locals: { human: @human_role.human, role: @human_role.role, date: @human_role.date, human_roles: @human_roles })
  end

  def destroy
    @human_role = HumanRole.find(params[:id])
    date = @human_role.date
    
    if @human_role
      @human_role.destroy
      @human_roles = HumanRole.where(date: date)
      render turbo_stream: 
        turbo_stream.replace("human-role-#{@human_role.date.iso8601}-#{@human_role.human_id}-#{@human_role.role_id}",
                            partial: "humans_roles/human_role",
                            locals: { human: @human_role.human, role: @human_role.role, date: @human_role.date, human_roles: @human_roles })
    end
  end

  private

  def human_role_params
    params.permit(:human_id, :role_id, :date)
  end

  def set_presenters; end
end
