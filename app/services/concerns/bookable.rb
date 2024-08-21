module Bookable
  extend ActiveSupport::Concern

  private

  def any_people?
    @booking.adults > 0
  end

  def available?(rooms)
    rooms.each do |room|
      if @booking.booking_type == "rooms"
        # Maison Communautaire
        # Not available if lodging reservations for the same date range
        if room.reservations
            .includes(:booking)
            .where(date: (@booking.from_date)..(@booking.to_date - 1.day), booking: { status: "confirmed", deleted_at: nil })
            .where.not(booking: { lodging_id: nil })
            .any?
          set_error_message("Cet hébergement n'est pas disponible à cette date.")
          return false
        end
      else
        # Gite
        # Not available if any reservations for the same date range
        if room.reservations
            .includes(:booking)
            .where(date: (@booking.from_date)..(@booking.to_date - 1.day), booking: { status: "confirmed", deleted_at: nil })
            .any? || !@booking.lodging.available_between?(@booking.from_date, @booking.to_date - 1.day)
          set_error_message("Cet hébergement n'est pas disponible à cette date.")
          return false
        end
      end
    end
  end


  def is_available?
    
    @stay.stay_items.where(item_type: StayItem::LODGING).each do |lodging_item|
      lod = Lodging.find(lodging_item.item_id)
      lod.rooms.each do |room|
        beds = room.beds
        if StayItemDate.includes(:stay)
            .where(booking_date: (lodging_item.start_date)..(lodging_item.end_date-1.day),
                   booked_item_type: StayItem::BED,
                   booked_item_id: [beds.collect{|b| b.id}],
                   stay: {status: "confirmed", draft: false, deleted_at: nil})
            .any?
         set_error_message("Le gîte #{lod.name} n'est pas disponible à cette date.")
          return false
        end

      end
  
    end

    @stay.stay_items.where(item_type: StayItem::ROOM).each do |room_item|
      room = Room.find(room_item.item_id)
      beds = room.beds
      if StayItemDate.includes(:stay)
                      .where(booking_date: (room_item.start_date)..(room_item.end_date-1.day),
                             booked_item_type: StayItem::BED,
                             booked_item_id: [beds.collect{|b| b.id}],
                             stay: {status: "confirmed", draft: false, deleted_at: nil})
            .any?
         set_error_message("La chambre #{room.name} n'est pas disponible à cette date.")
          return false
      end
  
    end
    
    @stay.stay_items.where(item_type: StayItem::BED).each do |bed_item|
      bed = Bed.find(bed_item.item_id)
      if StayItemDate.includes(:stay)
                      .where(booking_date: (bed_item.start_date)..(bed_item.end_date-1.day),
                             booked_item_type: StayItem::BED,
                             booked_item_id: [bed.id],
                             stay: {status: "confirmed", draft: false, deleted_at: nil})
            .any?
         set_error_message("Le lit #{bed.name} n'est pas disponible à cette date.")
          return false
      end
  
    end

    true
  end

  def build_reservations(rooms)
    rooms.each do |room|
      (@booking.from_date..(@booking.to_date - 1.day)).each do |date|
        @booking.reservations.build(
          room: room,
          date: date
        )
      end
    end
  end

  def get_rooms
    case @booking.booking_type
    when "lodging"
      @booking.lodging.rooms
    when "rooms"
      Room.where(id: @booking.room_ids&.compact_blank)
    else
      set_error_message(
        "Le type de réservation n'a pas pu être défini correctement."
      )
      nil
    end
  rescue
    set_error_message("Merci de vérifier si vous avez sélectionné un type d'hébergement.")
  end


  def get_beds

    beds = []
    @stay.lodgings.each do |lod|
      lod.rooms.each do |room|
        beds.concat(room.beds)
      end
    end

    @stay.rooms.each do |room|
      beds.concat(room.beds)
    end

    beds.concat(@stay.beds)

    if beds.uniq.length != beds.length
      set_error_message("Attention, vous avez placé 2 hébergements similaires dans la même réservation")
      nil
    end 

    beds

  end

  def notify_admin_on_create
    AdminMailer.booking_request(@booking).deliver_now
  end

  def notify_customer_on_create
    return if !@booking.email.present?
    if @booking.from_web?
      BookingMailer.booking_request(@booking).deliver_now
    elsif @booking.from_airbnb?
      # no notification
    else
      if @booking.confirmed?
        BookingMailer.booking_confirmed(@booking).deliver_now
      elsif @booking.pending?
        BookingMailer.booking_request(@booking).deliver_now
      end
    end
  end

  def set_invoice_status
    if @booking.invoice_wanted == "1"
      @booking.invoice_status = "requested"
    end
  end

  def set_tier
    if @booking.booking_type == "lodging"
      @booking.tier = @booking.tier_lodgings
    else
      @booking.tier = @booking.tier_rooms
    end
  end

  def terms_approved?
    if @booking.terms_approval != "1"
      set_error_message(
        "Merci d'accepter nos conditions générales de réservation. Il s'agit de la case à cocher au bas du formulaire."
      )
      return false
    end
    return true
  end

  def unset_lodging_id
    @booking.lodging_id = nil
  end

  def booking_params(params)
    params
      .require(:booking)
      .permit(
        :adults,
        :bedsheets,
        :booking_type,
        :children,
        :babies,
        :departure_time,
        :email,
        :estimated_arrival,
        :firstname,
        :from_date,
        :group_name,
        :invoice_status,
        :lastname,
        :lodging_id,
        :newsletter_subscription,
        :notes,
        :option_babysitting,
        :option_bread,
        :option_discgolf,
        :option_partyhall,
        :option_pizza_party,
        :payment_method,
        :payment_status,
        :platform,
        :phone,
        :price,
        :public_notes,
        :shown_price_cents,
        :status,
        :tier_lodgings,
        :tier_rooms,
        :to_date,
        :towels,
        :wifi,
        room_ids: [],
        payments_attributes: [
          :id,
          :amount,
          :payment_method,
          :_destroy
        ]
      )
  end



  def public_booking_params(params)
    params
      .require(:booking)
      .permit(
        :adults,
        :booking_type,
        :children,
        :babies,
        :comments,
        :estimated_arrival,
        :email,
        :firstname,
        :from_date,
        :invoice_wanted,
        :lastname,
        :lodging_id,
        :newsletter_subscription,
        :option_babysitting,
        :option_bread,
        :option_discgolf,
        :option_partyhall,
        :option_pizza_party,
        :payment_method,
        :phone,
        :shown_price_cents,
        :terms_approval,
        :tier_lodgings,
        :tier_rooms,
        :to_date,
        room_ids: []
      )
  end
end
