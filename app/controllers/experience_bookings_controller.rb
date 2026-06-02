class ExperienceBookingsController < ApplicationController
  before_action :authenticate_user!

  def index
    @experience_bookings = ExperienceBooking.includes(experience_availability: :experience, stay: :customer)
                                            .order(created_at: :desc)
                                            .limit(100)
  end

  def update
    @booking = ExperienceBooking.find(params[:id])
    if @booking.update(status: params[:status])
      head :ok
    else
      head :unprocessable_entity
    end
  end
end
