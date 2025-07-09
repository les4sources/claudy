namespace :db do
  desc "Migration des SpaceBookings vers Stay"
  task migrate_space_bookings_to_stays: :environment do
    puts "Début de la migration des SpaceBookings vers Stay..."
    total = SpaceBooking.count
    migrated = 0

    SpaceBooking.find_each do |space_booking|
      ActiveRecord::Base.transaction do
        puts "\nMigration du SpaceBooking ##{space_booking.id} (#{space_booking.firstname} #{space_booking.lastname}, email: #{space_booking.email})..."
        # 1. Client
        customer = Customer.find_by(email: space_booking.email)
        if customer && customer.email.present?
          puts "  - Client existant trouvé (id: #{customer.id})"
        else
          customer = Customer.create!(
            firstname: space_booking.firstname,
            lastname: space_booking.lastname,
            email: space_booking.email,
            phone: space_booking.phone
          )
          puts "  - Nouveau client créé (id: #{customer.id})"
        end

        # 2. Stay
        stay = Stay.new(
          user_id: User.first.id, # ou adapter selon besoin
          customer: customer,
          group_name: space_booking.group_name,
          status: space_booking.status,
          payment_status: space_booking.payment_status,
          invoice_status: space_booking.invoice_status,
          notes: space_booking.notes,
          token: space_booking.token,
          public_notes: space_booking.public_notes,
          departure_time: space_booking.departure_time,
          start_date: space_booking.from_date,
          end_date: space_booking.to_date,
          created_at: space_booking.created_at,
          updated_at: space_booking.updated_at,
          final_price_cents: space_booking.price_cents,
          adults: space_booking.persons.to_i,
          estimated_arrival: space_booking.arrival_time,
          deleted_at: space_booking.deleted_at,
          legacy_space_booking_id: space_booking.id,
          draft: false
        )

        # 3. Notes : caution/acompte
        notes_lines = []
        notes_lines << stay.notes if stay.notes.present?
        if space_booking.deposit_amount_cents.present? && space_booking.deposit_amount_cents > 0.0
          notes_lines << "Montant de la caution : #{space_booking.deposit_amount_cents / 100.0}€"
          puts "  - Caution détectée : #{space_booking.deposit_amount_cents / 100.0}€"
        end
        if space_booking.advance_amount_cents.present? && space_booking.advance_amount_cents > 0.0
          notes_lines << "Montant de l'acompte : #{space_booking.advance_amount_cents / 100.0}€"
          puts "  - Acompte détecté : #{space_booking.advance_amount_cents / 100.0}€"
        end
        stay.notes = notes_lines.reject(&:blank?).join("\n")

        stay.save!
        puts "  - Stay créé (id: #{stay.id})"

        # 4. Migration des espaces réservés (SpaceReservations)
        count_items = 0
        space_booking.space_reservations.each do |space_reservation|
          next if space_reservation.deleted_at.present?
          StayItem.create!(
            stay: stay,
            item_type: 'Space',
            item_id: space_reservation.space_id,
            start_date: space_reservation.date,
            end_date: space_reservation.date,
            duration: space_reservation.duration,
            quantity: 1,
            calculated_price_cents: 0
          )
          count_items += 1
        end
        puts "  - #{count_items} StayItem(s) (Space) créés pour ce séjour."

        # 5. Paiement
        if space_booking.payment_method.present? && space_booking.paid_amount_cents.to_f > 0.0
          payment = Payment.create!(
            stay: stay,
            payment_method: space_booking.payment_method,
            status: space_booking.payment_status,
            amount_cents: space_booking.paid_amount_cents || 0
          )
          payment.update_columns(created_at: space_booking.to_date.to_datetime, updated_at: space_booking.to_date.to_datetime)
          puts "  - Paiement créé (méthode: #{space_booking.payment_method}, montant: #{space_booking.paid_amount_cents} cts)"
        else
          puts "  - Aucun paiement à migrer."
        end

        # 6. Forcer created_at/updated_at si besoin
        stay.update_columns(created_at: space_booking.created_at, updated_at: space_booking.updated_at)
        migrated += 1
        puts "  > Migration du SpaceBooking ##{space_booking.id} terminée. (#{migrated}/#{total})"
      end
    end

    puts "\nMigration terminée : #{migrated} SpaceBookings migrés sur #{total}."
  end
end 