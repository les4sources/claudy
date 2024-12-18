class Public::StaysController < Public::BaseController
  layout "public_sheet"

  def show
    @stay = Stay.find_by!(token: params[:token]).decorate
    # @reservations_by_date = @stay.reservations.decorate.to_a.group_by { |r| r.date }
  rescue ActiveRecord::RecordNotFound
    raise ActionController::RoutingError.new('Not Found')
  end
end
