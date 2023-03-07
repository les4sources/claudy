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

  def build_space_reservations(spaces)
    spaces.each do |space|
      (@space_booking.from_date..(@space_booking.to_date - 1.day)).each do |date|
        @space_booking.space_reservations.build(
          space: space,
          date: date
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

  def set_invoice_status
    if @space_booking.invoice_wanted == "1"
      @space_booking.invoice_status = "requested"
    end
  end

  def space_booking_params(params)
    params
      .require(:space_booking)
      .permit(
        :email,
        :firstname,
        :from_date,
        :group_name,
        :invoice_wanted,
        :lastname,
        :newsletter_subscription,
        :notes,
        :payment_method,
        :payment_status,
        :phone,
        :price,
        :status,
        :tier,
        :to_date,
        space_ids: [],
      )
  end
end
