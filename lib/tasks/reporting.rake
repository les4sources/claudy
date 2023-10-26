namespace :reporting do
  desc "Nights for a date range"
  task :nights, ['from', 'to'] => :environment do |task, args|
    require 'csv'

    filename = "claudy-nights-#{args['from']}-#{args['to']}.csv"
    bookings = Booking.where(status: "confirmed")

    # Create a hash to store the total adults for each date
    date_totals = Hash.new(0)

    bookings.each do |booking|
      from_date = booking.from_date
      to_date = booking.to_date - 1.day

      current_date = from_date
      while current_date <= to_date
        date_totals[current_date] += booking.adults + booking.children
        current_date += 1.day
      end
    end

    CSV.open(filename, "w") do |csv|
      csv << ["date", "adultes et enfants"]
      date_totals.each do |date, sleepers|
        csv << [date.strftime("%d-%m-%Y"), sleepers]
      end
    end

    puts "CSV file '#{filename}' has been generated."
  end
end
