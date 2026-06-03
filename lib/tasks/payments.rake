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

  desc "Vérifie/répare le lien direct Payment -> Stay (issue #26)"
  task verify_stay_links: :environment do
    scope         = Payment.unscoped
    total         = scope.count
    with_stay     = scope.where.not(stay_id: nil).count
    without_stay  = scope.where(stay_id: nil)

    # Parmi ceux sans stay_id, lesquels POURRAIENT être reliés via leur Booking ?
    linkable = without_stay.to_a.select do |payment|
      payment.booking&.stay&.id.present?
    end

    puts "Payments (deleted inclus) : #{total}"
    puts "  avec stay_id            : #{with_stay}"
    puts "  sans stay_id            : #{without_stay.count}"
    puts "  dont reliables via Booking (backfill possible) : #{linkable.size}"

    if ENV["FIX"] == "1" && linkable.any?
      linkable.each { |p| p.update_column(:stay_id, p.booking.stay.id) }
      puts "→ #{linkable.size} payment(s) reliés (FIX=1)."
    elsif linkable.any?
      puts "→ Relancez avec FIX=1 pour backfiller ces #{linkable.size} payment(s)."
    end

    orphans = without_stay.count - linkable.size
    puts "Payments sans stay_id ni Booking->Stay (legacy sans séjour) : #{orphans}"
  end
end
