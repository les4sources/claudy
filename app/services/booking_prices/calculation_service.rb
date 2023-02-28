module BookingPrices
  class CalculationService < ServiceBase
    include Bookable

    attr_reader :booking, :amount

    def initialize
      @booking = Booking.new
      @report_errors = true
    end

    def run(params = {})
      context = {
        params: params
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      @booking.attributes = booking_params(params)
      @amount = calculate_price
      true
    end

    private

    def calculate_price
      case @booking.booking_type
      when "lodging"
        calculate_price_for_lodging
      when "rooms"
        calculate_price_for_rooms
      end
    end

    def calculate_price_for_rooms
      # tier pricing (25 / 35 / 45)
      # price per person (adults and children)
      # 20% discount starting from 3rd night
      total_amount = 0
      case @booking.tier_rooms
      when "solidaire"
        night_price = 2500
      when "neutre"
        night_price = 3500
      when "soutien"
        night_price = 4500
      end
      nights_count = 0
      (@booking.from_date..@booking.to_date.yesterday).each do |date|
        nights_count = nights_count + 1
        if nights_count > 2
          night_amount = night_price * 0.8 # 20% discount
        else
          night_amount = night_price
        end
        total_amount = total_amount + night_amount
      end
      total_amount * (@booking.adults + @booking.children)
    end

    def calculate_price_for_lodging
      # tier pricing (-25%, standard, +25%)
      # 20% discount starting from 2nd night
      # 6% discount on weekend nights (Fri and Sat)
      total_amount = 0
      case @booking.tier_lodgings
      when "solidaire"
        night_price = @booking.lodging.price_night_cents * 0.75
      when "neutre"
        night_price = @booking.lodging.price_night_cents
      when "soutien"
        night_price = @booking.lodging.price_night_cents * 1.25
      end
      nights_count = 0
      (@booking.from_date..@booking.to_date.yesterday).each do |date|
        nights_count = nights_count + 1
        if date.wday == 5 || date.wday == 6 # Fri, Sat
          night_amount = night_price * 0.94 # 6% discount
        else
          night_amount = night_price
        end
        if nights_count > 1
          night_amount = night_amount * 0.8 # 20% discount
        end
        total_amount = total_amount + night_amount
      end
      total_amount
    end
  end
end

  # // calculate booking price
  # calculateAmount(nights) {
  #   console.log('bookingType', this.getSelectedBookingType())
  #   try {
  #     if (this.forLodging()) {
  #       // const nightPrice = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0].dataset.bookingPriceNightParam
  #       return this.calculateAmountForLodging(nights, this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0])
  #       // console.log('nightPrice', nightPrice)
  #       // return nights * nightPrice
  #     } else {
  #       const tierPrice = document.querySelector('.selected-tier').dataset.bookingTierAmountParam
  #       console.log('tierPrice', tierPrice)
  #       return nights * tierPrice * this.getPeopleCount()
  #     }
  #   } catch {
  #     return -1
  #   }
  # }

  # calculateAmountForLodging(nights, lodgingInput) {
  #   const nightPrice = lodgingInput.dataset.bookingPriceNightParam
  #   const weekendDiscount = lodgingInput.dataset.bookingWeekendDiscountParam
  #   var days = []
  #   for (var m = this.getFromDate(); m.isBefore(this.getToDate()); m.add(1, 'days')) {
  #     days.push(m.day())
  #   }
  #   // how many weekends? (for the discount)
  #   days = days.filter(day => day == 5 || day == 6);
  #   console.log('days', days)
  #   var amount = nights * nightPrice
  #   const weekendsCount = Math.floor(days.length / 2)
  #   console.log('weekendsCount', weekendsCount)
  #   console.log('weekendDiscount', weekendDiscount)
  #   amount = amount - (weekendsCount * weekendDiscount)
  #   return amount
  # }

  # // NOT CALLED anymore
  # setPrice() {
  #   const adults = parseInt(this.adultsInputTarget.value) || 0
  #   const children = parseInt(this.childrenInputTarget.value) || 0
  #   const fromDate = moment(this.fromDateInputTarget.value)
  #   const toDate = moment(this.toDateInputTarget.value)
  #   console.log('setPrice', adults, children, fromDate, toDate)
  #   if ((adults == 0 && children == 0) || !fromDate.isValid() || !toDate.isValid()) {
  #     console.log('Sorry, we can\'t preview the price')
  #     this.showPriceCalculationNotice()
  #   } else {
  #     const nights = toDate.diff(fromDate, 'days')
  #     console.log('toDate and fromDate', toDate, fromDate)
  #     if (nights < 1) {
  #       console.log('Oops, less than one night', nights)
  #       this.showPriceCalculationNotice()
  #     } else {
  #       const amount = this.calculateAmount(nights)
  #       console.log('All good, we can preview the price', amount, nights)
  #       if (amount >= 0) {
  #         this.setInputValue(this.shownPriceInputTarget, amount)
  #         this.showPricePreview(amount)
  #       }
  #     }
  #   }
  # }
