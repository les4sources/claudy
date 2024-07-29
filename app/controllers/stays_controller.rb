class StaysController < BaseController


 def index
 	@stays = Stay.unscoped.current_and_future
  @bookings = Booking.unscoped.current_and_future
 end


 def new
    if !params[:source_booking_id].nil?
      #duplication_service = Bookings::DuplicateService.new
      #duplication_service.run!(source_booking_id: params[:source_booking_id])
      #@stay = duplication_service.booking
    else
      @stay = Stay.new(
        platform: "direct",
        status: "init",
        start_date: params.fetch("date", nil)
      )
    end
    #@stay.build_user
    @stay.build_customer
    Rails.logger.info(@stay.inspect)
    Rails.logger.info(@stay.customer)
    @lodgings = Lodging.all
  end


  def create
    service = Stays::CreateService.new
    if service.run(params)
      redirect_to service.stay,
                  notice: "Merci, la réservation a été enregistrée."
    else
      @stay = service.stay
      set_error_flash(service.stay, "<strong>Cette réservation n'a pas pu être enregistrée, merci de vérifier les éléments suivants:</strong><br>#{service.error_message}")
      render :new, status: :unprocessable_entity
    end
  end


   private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "bookings",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end

end