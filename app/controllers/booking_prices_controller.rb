class BookingPricesController < BaseController
  def create
    service = BookingPrices::CalculationService.new
    if service.run(params)
      render json: { amount: service.amount },
             status: :ok
    else
      render json: { amount: service.amount }, 
             status: :unprocessable_entity
    end
  end

  private

  def set_presenters; end
end