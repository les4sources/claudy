class PaylinksController < BaseController
  before_action :get_paylink, only: [:show, :edit, :update, :destroy]
  before_action :ensure_frame_response, only: [:new, :edit]

  layout "modal"

  def index
    @paylinks = PaylinkDecorator.decorate_collection(Paylink.all.order(created_at: :desc))
    render layout: "application"
  end

  def new
    @booking = Booking.find(params[:booking_id])
    @paylink = @booking.paylinks.new(amount_cents: nil)
  end

  def create
    service = Paylinks::CreateService.new(booking_id: @booking.id)
    respond_to do |format|
      if service.run(params)
        format.turbo_stream { @paylink = PaylinkDecorator.decorate(service.paylink) }
        format.html { redirect_to booking_url(service.booking), notice: "Le paylink a été créé." }
        format.json { render :show, status: :created, location: service.paylink }
      else
        format.html { 
          @paylink = service.paylink
          render :new, status: :unprocessable_entity 
        }
        format.json { render json: service.paylink.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    service = Paylinks::DestroyService.new(paylink_id: @paylink.id)
    if service.run
      respond_to do |format|
        format.turbo_stream { @paylink = PaylinkDecorator.decorate(service.paylink) }
        format.html { redirect_to booking_url(@booking), notice: "Le paylink a été supprimé." }
        format.json { head :no_content }
      end
    end
  end

  private

  # def get_booking
  #   breadcrumb "Hébergements", :bookings_path, match: :exact
  #   @booking = Booking.find(params[:booking_id])
  # end

  def get_paylink
    @paylink = Paylink.find(params[:id])
  end

  def ensure_frame_response
    return unless Rails.env.development?
    redirect_to root_path unless turbo_frame_request?
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "accounting",
      active_secondary: "paylinks"
    )
    @accounting_view = true
  end
end
