module SpaceBookable
  extend ActiveSupport::Concern

  private

  def available?(spaces)
    spaces.each do |space|
      if space.space_reservations
          .includes(:space_booking)
          .where(date: (@space_booking.from_date)..(@space_booking.to_date - 1.day), space_booking: { status: "confirmed" })
          .any?
        set_error_message("Cet espace n'est pas disponible à cette date.")
        return false
      end
    end
  end

  def build_space_reservations(spaces, duration)
    spaces.each do |space|
      (@space_booking.from_date..@space_booking.to_date).each do |date|
        @space_booking.space_reservations.build(
          space: space,
          date: date,
          duration: duration
        )
      end
    end
  end

  def get_spaces
    Space.where(id: @space_booking.space_ids&.compact_blank)
  end

  def notify_customer_on_create
    return if !@space_booking.email.present?
    if @space_booking.confirmed?
      SpaceBookingMailer.space_booking_confirmed(@space_booking).deliver_now
    elsif @space_booking.pending?
      SpaceBookingMailer.space_booking_request(@space_booking).deliver_now
    end
  end

  def space_booking_params(params)
    params
      .require(:space_booking)
      .permit(
        :advance_amount,
        :arrival_time,
        :departure_time,
        :deposit_amount,
        :duration,
        :email,
        :event_id,
        :firstname,
        :from_date,
        :group_name,
        :invoice_status,
        :lastname,
        :newsletter_subscription,
        :notes,
        :option_kitchenware,
        :option_beamer,
        :option_wifi,
        :option_tables,
        :paid_amount,
        :payment_method,
        :payment_status,
        :persons,
        :phone,
        :price,
        :public_notes,
        :status,
        :tier,
        :to_date,
        space_ids: [],
      )
  end
end
