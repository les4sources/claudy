class PaymentsController < BaseController
  before_action :get_reservation, except: [:index, :show, :destroy]
  before_action :get_payment, only: [:show, :edit, :update, :destroy]
  before_action :ensure_frame_response, only: [:new, :edit]

  layout "modal"

  def index
    @payments = PaymentDecorator.decorate_collection(Payment.all.order(created_at: :desc))
    render layout: "application"
  end

  def show
    breadcrumb "Paiements", :payments_path, match: :exact
    @payment = PaymentDecorator.decorate(@payment)
    render layout: "application"
  end

  def new
    init_reservation
  end

  def create
    service = init_create_service
    respond_to do |format|
      if service.run(params)
        format.turbo_stream { @payment = PaymentDecorator.decorate(service.payment) }
        format.html { redirect_to get_reservation_url(service), notice: "Le paiement a été enregistré." }
        format.json { render :show, status: :created, location: service.payment }
      else
        format.html { 
          @payment = service.payment
          render :new, status: :unprocessable_entity 
        }
        format.json { render json: service.payment.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    service = Payments::UpdateService.new(payment_id: params[:id])
    respond_to do |format|
      if service.run(params)
        format.turbo_stream { @payment = PaymentDecorator.decorate(service.payment) }
        format.html { redirect_to get_reservation_url(service.reservation), notice: "Le paiement a été mis à jour." }
        format.json { render :show, status: :ok, location: service.payment }
      else
        format.html { 
          @payment = service.payment
          render :edit, status: :unprocessable_entity 
        }
        format.json { render json: service.payment.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    service = Payments::DestroyService.new(payment_id: @payment.id)
    if service.run
      respond_to do |format|
        format.turbo_stream { @payment = PaymentDecorator.decorate(service.payment) }
        format.html { redirect_to get_reservation_url(service), notice: "Le paiement a été supprimé." }
        format.json { head :no_content }
      end
    end
  end

  private

  def init_reservation
    if params[:booking_id]
      @payment = @booking.payments.new(amount_cents: nil)
      if @booking.from_airbnb?
        @payment.payment_method = "airbnb"
      end
    elsif params[:stay_id]
      @payment = @stay.payments.new(amount_cents: nil)
      if @stay.from_airbnb?
        @payment.payment_method = "airbnb"
      end
    end
  end

  def init_create_service
    if @booking
      Payments::CreateService.new(reservation_type: 'Booking', reservation_id: @booking.id)
    elsif @stay
      Payments::CreateService.new(reservation_type: 'Stay', reservation_id: @stay.id)
    end

  end

  def get_reservation
    if params[:booking_id]
      breadcrumb "Hébergements", :bookings_path, match: :exact
      @booking = Booking.find(params[:booking_id])
    elsif params[:stay_id]
      breadcrumb "Séjours", :stays_path, match: :exact
      @stay = Stay.find(params[:stay_id])
    elsif params[:payment_id]
      payment = Payment.find(params[:payment_id])
      @booking = payment.booking unless payment.booking.nil?
      @stay = payment.stay unless payment.stay.nil?
    end  
  end

  def get_reservation_url(service)
    if @booking
      booking_url(service.reservation)
    elsif @stays
      stay_url(service.reservation)
    end
  end


  def get_payment
    @payment = Payment.find(params[:id])
  end

  def ensure_frame_response
    return unless Rails.env.development?
    redirect_to root_path unless turbo_frame_request?
  end

  def payment_params
    params
      .require(:payment)
      .permit(
        :amount, 
        :payment_method, 
        :status
      )
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "accounting",
      active_secondary: "payments"
    )
    @accounting_view = true
  end
end
