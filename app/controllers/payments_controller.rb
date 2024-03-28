class PaymentsController < BaseController
  before_action :get_booking, except: [:index, :pay]
  before_action :get_payment, only: [:show, :edit, :update, :destroy, :pay]
  before_action :ensure_frame_response, only: [:new, :edit]

  layout "modal"

  def index
    @payments = PaymentDecorator.decorate_collection(Payment.all.order(created_at: :desc))
    render layout: "application"
  end

  def new
    @payment = @booking.payments.new(amount_cents: nil)
    if @booking.from_airbnb?
      @payment.payment_method = "airbnb"
    end
  end

  def create
    service = Payments::CreateService.new(booking_id: @booking.id)
    respond_to do |format|
      if service.run(params)
        format.turbo_stream { @payment = PaymentDecorator.decorate(service.payment) }
        format.html { redirect_to booking_url(service.booking), notice: "Le paiement a été enregistré." }
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
        format.html { redirect_to booking_url(service.booking), notice: "Le paiement a été mis à jour." }
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
        format.html { redirect_to booking_url(@booking), notice: "Le paiement a été supprimé." }
        format.json { head :no_content }
      end
    end
  end

  private

  def get_booking
    breadcrumb "Hébergements", :bookings_path, match: :exact
    @booking = Booking.find(params[:booking_id])
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
