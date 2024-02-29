namespace :payments do
  task delete_payments: :environment do |task|
    Payment.destroy_all
  end

  desc "Migrating - Create payments for existing bookings"
  task create_payments: :environment do |task|
    # paid bookings
    Booking.where(payment_status: "paid", status: "confirmed").each do |booking|
      booking.payments.create(
        amount_cents: booking.price_cents,
        payment_method: booking.payment_method,
        created_at: booking.created_at
      )
    end
    # partially paid bookings
    Booking.where(payment_status: "partially_paid", status: "confirmed").each do |booking|
      puts "Partially paid: #{Rails.application.routes.url_helpers.booking_url(booking, only_path: true)}"
    end
    puts "Done!"
  end
end
