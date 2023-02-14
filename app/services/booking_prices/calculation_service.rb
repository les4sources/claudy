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
      1234
    end

    def calculate_price_for_lodging
      5678
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
