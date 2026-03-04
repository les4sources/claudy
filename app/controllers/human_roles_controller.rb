class HumanRolesController < BaseController
  def create
    existing = HumanRole.find_by(
      human_id: params[:human_id],
      role_id: params[:role_id],
      date: params[:date]
    )

    if existing.nil?
      @human_role = HumanRole.create!(human_role_params.merge(status: :backup))
    elsif existing.backup?
      existing.update!(status: :selected)
      @human_role = existing
    elsif existing.selected?
      @human_role = existing
      existing.destroy
    end

    @human_roles = HumanRole.where(date: @human_role.date)
  end

  def destroy
    @human_role = HumanRole.find(params[:id])
    date = @human_role.date
    @human_role.destroy
    @human_roles = HumanRole.where(date: date)
  end

  private

  def human_role_params
    params.permit(:human_id, :role_id, :date)
  end

  def set_presenters; end
end
