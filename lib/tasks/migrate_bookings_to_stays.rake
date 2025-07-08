namespace :migration do
  desc "Migrer les bookings vers les stays et customers"
  task migrate_bookings_to_stays: :environment do
    puts "🚀 Début de la migration des bookings vers les stays..."
    
    # Compter les bookings à migrer
    total_bookings = Booking.unscoped.count
    puts "📊 #{total_bookings} bookings à migrer"
    
    # Garder trace des IDs des stays créés pour rollback en cas d'erreur
    created_stay_ids = []
    created_customer_ids = []
    
    # Transaction pour s'assurer de la cohérence
    ActiveRecord::Base.transaction do
      begin
        Booking.unscoped.find_each.with_index do |booking, index|
          puts "⏳ Migration du booking #{index + 1}/#{total_bookings} (ID: #{booking.id})"
          
          # 1. Créer ou récupérer le customer
          customer = nil
          if booking.email.present?
            # Essayer de récupérer un customer existant basé sur l'email
            customer = Customer.find_by(email: booking.email)
            if customer.nil?
              customer = Customer.create!(
                email: booking.email,
                firstname: booking.firstname,
                lastname: booking.lastname,
                phone: booking.phone,
                created_at: booking.created_at,
                updated_at: booking.updated_at
              )
              created_customer_ids << customer.id
              puts "  ✅ Nouveau customer créé avec email (ID: #{customer.id})"
            else
              puts "  🔄 Customer existant récupéré (ID: #{customer.id})"
            end
          else
            # Créer un customer même sans email
            customer = Customer.create!(
              email: booking.email, # sera nil ou ""
              firstname: booking.firstname,
              lastname: booking.lastname,
              phone: booking.phone,
              created_at: booking.created_at,
              updated_at: booking.updated_at
            )
            created_customer_ids << customer.id
            puts "  ✅ Nouveau customer créé sans email (ID: #{customer.id})"
          end
          
          # 2. Créer le stay
          stay = Stay.new(
            user_id: 1, # Utilisateur par défaut pour la migration
            legacy_booking_id: booking.id, # Référence vers l'ancien booking
            customer: customer,
            start_date: booking.from_date,
            end_date: booking.to_date,
            status: booking.status,
            adults: booking.adults,
            children: booking.children,
            babies: booking.babies,
            estimated_arrival: booking.estimated_arrival,
            departure_time: booking.departure_time,
            token: booking.token,
            platform: booking.platform,
            notes: booking.notes,
            comments: booking.comments,
            draft: false, # Les bookings existants ne sont pas des brouillons
            invoice_status: booking.invoice_status,
            group_name: booking.group_name,
            public_notes: booking.public_notes,
            deleted_at: booking.deleted_at,
            final_price_cents: booking.price_cents || 0
          )
          
          # Définir les timestamps manuellement
          stay.created_at = booking.created_at
          stay.updated_at = booking.updated_at
          
          stay.save!
          created_stay_ids << stay.id
          puts "  ✅ Stay créé (ID: #{stay.id})"
          
          # 3. Créer les StayItems 
          if booking.lodging_id.present?
            # 3a. Créer le StayItem pour le lodging si lodging_id existe
            stay_item = StayItem.create!(
              stay: stay,
              item_type: StayItem::LODGING,
              item_id: booking.lodging_id,
              start_date: booking.from_date,
              end_date: booking.to_date,
              quantity: 1,
              adults_count: booking.adults,
              children_count: booking.children,
              babies_count: booking.babies
            )
            puts "  ✅ StayItem pour lodging créé (ID: #{stay_item.id})"
          elsif booking.reservations.any?
            # 3b. Créer les StayItems pour les rooms via les reservations (seulement si pas de lodging)
            booking.reservations.group_by(&:room_id).each do |room_id, reservations|
              stay_item = StayItem.create!(
                stay: stay,
                item_type: StayItem::ROOM,
                item_id: room_id,
                start_date: booking.from_date,
                end_date: booking.to_date,
                quantity: 1,
                adults_count: booking.adults,
                children_count: booking.children,
                babies_count: booking.babies
              )
              puts "  ✅ StayItem pour room #{room_id} créé (ID: #{stay_item.id}) - #{reservations.length} nuits"
            end
          end
          
          # 4. Mettre à jour les paiements existants pour rattacher le stay
          Payment.where(booking_id: booking.id).find_each do |payment|
            payment.update!(stay_id: stay.id)
            puts "  🔗 Paiement #{payment.id} mis à jour avec stay_id=#{stay.id}"
          end
          
          # 5. Mettre à jour le payment_status du stay
          stay.set_payment_status
          
          puts "  🎯 Booking #{booking.id} migré avec succès vers Stay #{stay.id}"
        end
        
        puts "🎉 Migration terminée avec succès !"
        puts "📈 #{created_stay_ids.length} stays créés"
        puts "👥 #{created_customer_ids.length} nouveaux customers créés"
        
      rescue => e
        puts "❌ Erreur durant la migration: #{e.message}"
        puts "🔄 Rollback en cours..."
        
        # Supprimer tous les stays créés (cascade supprimera les stay_items et payments liés)
        Stay.where(id: created_stay_ids).destroy_all
        puts "🗑️ #{created_stay_ids.length} stays supprimés"
        
        # Supprimer les nouveaux customers créés (seulement ceux sans stays restants)
        created_customer_ids.each do |customer_id|
          customer = Customer.find_by(id: customer_id)
          if customer && customer.stays.empty?
            customer.destroy
            puts "🗑️ Customer #{customer_id} supprimé"
          end
        end
        
        puts "💥 Migration annulée - rollback effectué"
        raise e # Re-lever l'erreur pour faire échouer la transaction
      end
    end
  end

  desc "Vérifier l'état avant la migration"
  task check_migration_status: :environment do
    puts "🔍 Vérification de l'état avant migration..."
    
    bookings_count = Booking.unscoped.count
    stays_count = Stay.unscoped.count
    customers_count = Customer.count
    
    puts "📊 État actuel :"
    puts "  - Bookings : #{bookings_count}"
    puts "  - Stays : #{stays_count}"
    puts "  - Customers : #{customers_count}"
    
    if stays_count > 0
      puts "⚠️  ATTENTION : Il y a déjà #{stays_count} stays en base !"
      puts "   Assurez-vous que c'est voulu avant de lancer la migration."
    end
    
    # Vérifier les bookings avec des données manquantes
    bookings_without_email = Booking.unscoped.where(email: [nil, ""]).count
    bookings_without_dates = Booking.unscoped.where("from_date IS NULL OR to_date IS NULL").count
    bookings_with_lodging = Booking.unscoped.where.not(lodging_id: nil).count
    bookings_with_reservations = Booking.unscoped.joins(:reservations).distinct.count
    
    puts "\n🔎 Analyse des données :"
    puts "  - Bookings sans email : #{bookings_without_email}"
    puts "  - Bookings sans dates : #{bookings_without_dates}"
    puts "  - Bookings avec lodging : #{bookings_with_lodging}"
    puts "  - Bookings avec réservations de rooms : #{bookings_with_reservations}"
    
    if bookings_without_email > 0
      puts "  ⚠️  Ces bookings seront migrés avec un customer ayant un email vide"
    end
    
    if bookings_without_dates > 0
      puts "  ❌ Ces bookings causeront des erreurs - il faut les corriger d'abord"
    end
    
    unique_emails = Booking.unscoped.where.not(email: [nil, ""]).distinct.count(:email)
    puts "  - Emails uniques : #{unique_emails} (nombre de customers potentiels)"
    
    total_reservations = Reservation.count
    puts "  - Total réservations : #{total_reservations}"
  end

  desc "Nettoyer les stays et customers créés par la migration (DANGER)"
  task clean_migrated_data: :environment do
    puts "⚠️  ATTENTION : Cette tâche va supprimer TOUS les stays et customers !"
    puts "   Appuyez sur Entrée pour continuer ou Ctrl+C pour annuler..."
    STDIN.gets
    
    stays_count = Stay.unscoped.count
    customers_count = Customer.count
    
    puts "🗑️  Suppression en cours..."
    
    # Supprimer tous les stays (cascade sur stay_items et payments)
    Stay.unscoped.destroy_all
    puts "  ✅ #{stays_count} stays supprimés"
    
    # Supprimer tous les customers
    Customer.destroy_all
    puts "  ✅ #{customers_count} customers supprimés"
    
    puts "🧹 Nettoyage terminé !"
  end

  desc "Afficher un rapport de migration"
  task migration_report: :environment do
    puts "📋 Rapport de migration"
    puts "=" * 50
    
    bookings_count = Booking.unscoped.count
    stays_count = Stay.unscoped.count
    customers_count = Customer.count
    payments_count = Payment.count
    stay_items_count = StayItem.count
    
    puts "📊 Données actuelles :"
    puts "  - Bookings : #{bookings_count}"
    puts "  - Stays : #{stays_count}"
    puts "  - Customers : #{customers_count}"
    puts "  - Payments : #{payments_count}"
    puts "  - StayItems : #{stay_items_count}"
    
    if stays_count > 0
      puts "\n🎯 Détails des stays :"
      puts "  - Avec customer : #{Stay.joins(:customer).count}"
      puts "  - Sans customer : #{Stay.where(customer: nil).count}"
      puts "  - Avec paiements : #{Stay.joins(:payments).distinct.count}"
      puts "  - Avec stay_items : #{Stay.joins(:stay_items).distinct.count}"
      
      status_breakdown = Stay.group(:status).count
      puts "\n📈 Répartition par status :"
      status_breakdown.each do |status, count|
        puts "  - #{status || 'nil'} : #{count}"
      end
    end
  end
end 