class StaysController < BaseController
 
 def index
 	@stays = StayDecorator.decorate_collection(Stay.unscoped.current_and_future)  
 end

 def past
    @stays = StayDecorator
      .decorate_collection(Stay.past.paginate(page: params[:page], per_page: 40))
  end

 def new
    if !params[:source_booking_id].nil?
      #duplication_service = Bookings::DuplicateService.new
      #duplication_service.run!(source_booking_id: params[:source_booking_id])
      #@stay = duplication_service.booking
    else
      @stay = Stay.create(
        draft: true,
        platform: "direct",
        status: "init",
        start_date: params.fetch("date", nil),
        user_id: current_user.id,
        token: Stay.generate_token
      )
      @stay.payments.build(amount_cents: nil)      
    end
    @stay.build_customer
  end

  # stays are created on init, with stay.draft == true
  # def create
  #   service = Stays::CreateService.new
  #   if service.run(params)
  #     redirect_to service.stay,
  #                 notice: "Merci, la réservation a été enregistrée."
  #   else
  #     @stay = service.stay
  #     set_error_flash(service.stay, "<strong>Cette réservation n'a pas pu être enregistrée, merci de vérifier les éléments suivants:</strong><br>#{service.error_message}")
  #     render :new, status: :unprocessable_entity
  #   end
  # end

  def edit
    @stay = Stay.find_by!(id: params[:id])
    @stay.build_customer if @stay.customer.nil?
    @stay.payments.build(amount_cents: nil) if @stay.payments.empty?
  end

  def update
    service = Stays::UpdateService.new(stay_id: params[:id])
    respond_to do |format|
      if service.run(params)
        format.html { redirect_to service.stay, notice: "Le séjour a été enregistré/mise à jour." }
        format.json { render :show, status: :ok, location: service.stay }
      else
        set_error_flash(service.stay, "<strong>Cette réservation n'a pas pu être enregistrée, merci de vérifier les éléments suivants:</strong><br>#{service.error_message}")
        format.html { 
          @stay = service.stay
          render :edit, 
                 status: :unprocessable_entity,
                 alert: service.error_message
        }
        format.json { render json: service.error_message, status: :unprocessable_entity }
      end
    end
  end

  def save_date
    stay = Stay.find(params[:id])
    stay.update(stay_dates_params)
  end

  def show
    @stay = Stay.unscoped.find_by!(id: params[:id]).decorate
    @lodgings = @stay.lodgings
    @rooms_by_date = @stay.rooms_by_date
    @experiences_by_date = @stay.experiences_by_date
    @products_by_date = @stay.products_by_date
    @rental_items_by_date = @stay.rental_items_by_date
    @spaces_by_date = @stay.spaces_by_date
    @reservations_by_date = @stay.stay_item_dates.where(booked_item_type: StayItem::ROOM).decorate.to_a.group_by { |r| r.booking_date }
    Rails.logger.info("$$$$$$$$ #{@reservations_by_date}")
  end

   def destroy
    @stay = Stay.find_by!(id: params[:id])
    @stay.soft_delete!(validate: false)
    @stay.create_activity(:destroy)
    redirect_to stays_url,
                status: :see_other,
                notice: "Le séjour a été supprimé."
  end

   private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "stays",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end

  
  def stay_dates_params
    params.require(:stay).permit(:start_date, :end_date)
  end

end