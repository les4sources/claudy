class StaysController < BaseController


 def index
 	@stays = StayDecorator.decorate_collection(Stay.unscoped.current_and_future)
  #@bookings = Booking.unscoped.current_and_future
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
    @stay.build_customer
    
    @stay_items = StayItem.build
  
  end


  def create
    Rails.logger.info("**********************************")
    Rails.logger.info(params.inspect)
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


  def show
    @stay = Stay.unscoped.find_by!(id: params[:id]).decorate
    @lodgings = @stay.lodgings
    @rooms_by_date = @stay.rooms_by_date
    @experiences_by_date = @stay.experiences_by_date
    @products_by_date = @stay.products_by_date
    @rental_items_by_date = @stay.rental_items_by_date
    @spaces_by_date = @stay.spaces_by_date
  
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