class PaymentsController < BaseController
  before_action :get_booking
  before_action :get_payment, only: [:show, :edit, :update, :destroy]
  before_action :ensure_frame_response, only: [:new, :edit]

  layout "modal"

  breadcrumb "Hébergements", :bookings_path, match: :exact
  breadcrumb "Paiements", :booking_payments_path, match: :exact

  def new
    @payment = @booking.payments.new
    if @booking.from_airbnb?
      @payment.payment_method = "airbnb"
    end
  end

  def create
    @payment = @booking.payments.new(payment_params)
    respond_to do |format|
      if @payment.save
        format.turbo_stream { render turbo_stream: turbo_stream.prepend("payments-#{@booking.id}", partial: 'payments/payment', locals: { payment: PaymentDecorator.new(@payment) }) }
        format.html { redirect_to booking_url(@booking), notice: "Le paiement a été enregistré." }
        format.json { render :show, status: :created, location: @payment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @payment.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    respond_to do |format|
      if @payment.update(payment_params)
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@payment, partial: "payments/payment", locals: { payment: PaymentDecorator.new(@payment) }) }
        format.html { redirect_to booking_url(@booking), notice: "Le paiement a été mis à jour." }
        format.json { render :show, status: :ok, location: @payment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @payment.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @payment.soft_delete!(validate: false)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@payment) }
      format.html { redirect_to booking_url(@booking), notice: "Le paiement a été supprimé." }
      format.json { head :no_content }
    end
  end

  private

  def get_booking
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
      active_primary: "bookings",
      active_secondary: "payments"
    )
  end
end
