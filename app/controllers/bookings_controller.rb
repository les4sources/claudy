class BookingsController < ApplicationController
  def index
    @bookings = Booking.all
  end

  def show
    @booking = Booking.find_by!(id: params[:id])
  end

  def new
    @booking = Booking.new
  end

  def create
    @booking = Booking.new(booking_params)

    respond_to do |format|
      if @booking.save
        format.html { redirect_to @booking, notice: "La réservation a été enregistrée." }
        format.json { render :show, status: :created, location: @booking }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @booking.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @booking = Booking.find_by!(id: params[:id])
  end

  def update
    @booking = Booking.find_by!(id: params[:id])
    respond_to do |format|
      if @booking.update(booking_params)
        format.html { redirect_to @booking, notice: "La réservation a été mise à jour." }
        format.json { render :show, status: :ok, location: @booking }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @booking.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @booking = Booking.find_by!(id: params[:id])
    @booking.destroy
    respond_to do |format|
      format.html { redirect_to bookings_url, status: :see_other, notice: "La réservation a été supprimée." }
      format.json { head :no_content }
    end
  end

  private

  def booking_params
    params
      .require(:booking)
      .permit(
        :firstname,
        :lastname,
        :phone,
        :email,
        :from_date,
        :to_date,
        :status,
        :adults,
        :children,
        :price,
        :payment_status,
        :payment_method,
        :bedsheets,
        :towels,
        :notes
      )
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "bookings",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end
end
