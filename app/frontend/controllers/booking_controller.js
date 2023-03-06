import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'
import moment from "moment"

export default class extends Controller {
  static targets = [
    'adultsInput',
    'bookingTypeOptions',
    'childrenInput',
    'divLodgings',
    'divRooms',
    'fromDateInput',
    'lodgingsPanel',
    'lodgingRadioButton',
    'otherBookings',
    'partyHallOption',
    'priceCalculationNotice',
    'priceDiv',
    'pricePreview',
    'priceSection',
    'roomsPanel',
    'shownPriceInput',
    'tierButton',
    'tierPricingForRooms',
    'tierPricingForLodgings',
    'tierInput',
    'tierRoomsRadioButton',
    'tierLodgingsRadioButton',
    'toDateInput'
  ]
  // static targets = [
  //   'adultsInput',
  //   'bookingTypeField',
  //   'childrenInput',
  //   'fromDateInput',
  //   'lodgingRadioButton',
  //   'partyHallSection',
  //   'priceCalculationNotice',
  //   'priceDiv',
  //   'pricePreview',
  //   'roomsTab',
  //   'shownPriceInput',
  //   'tierButton',
  //   'tierCard',
  //   'tierPricing',
  //   'tierInput',
  //   'toDateInput'
  // ]

  connect() {
    console.log('connect booking')
  }

  initialize() {
    console.log('initialize booking', this.getSelectedBookingType())
    this.drawForm()

    // // initialize form
    // if (this.bookingTypeFieldTarget.value == 'lodging') {
    //   // hide tier pricing
    //   this.toggleTierPricing()
    //   this.setPrice()
    //   // toggle 'party hall' section if Grand-Duc checked
    //   const selectedLodging = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0]
    //   if (selectedLodging !== undefined) {
    //     this.togglePartyHallSection(selectedLodging.dataset.bookingPartyHallAvailabilityParam)
    //   }
    // } else {
    //   this.roomsTabTarget.click()
    //   if (this.tierInputTarget.value) {
    //     this.setTier()
    //   }
    // }
  }

  drawForm(e) {
    this.toggleLodgingsDiv()
    this.toggleRoomsDiv()
    this.togglePriceDetails()
    this.togglePartyHallOption()
  }

  getFromDate() {
    return moment(this.fromDateInputTarget.value)
  }

  getPeopleCount() {
    const adults = parseInt(this.adultsInputTarget.value) || 0
    const children = parseInt(this.childrenInputTarget.value) || 0
    return adults + children
  }

  getToDate() {
    return moment(this.toDateInputTarget.value)
  }

  getSelectedBookingType() {
    return this.bookingTypeOptionsTargets.find(button => button.checked).value
  }

  getSelectedLodging() {
    const selectedLodging = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0]
    return selectedLodging || null
  }

  getSelectedLodgingValue() {
    try {
    const selectedLodging = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0]
    return selectedLodging.value || null
    } catch (err) {
      return null
    }
  }

  getSelectedTierLodgings() {
    if (this.tierLodgingsRadioButtonTargets.filter(radio => radio.checked).length) {
      return this.tierLodgingsRadioButtonTargets.filter(radio => radio.checked)[0].value
    } else {
      return "neutre"
    }
  }

  getSelectedTierRooms() {
    if (this.tierRoomsRadioButtonTargets.filter(radio => radio.checked).length) {
      return this.tierRoomsRadioButtonTargets.filter(radio => radio.checked)[0].value
    } else {
      return "neutre"
    }
  }

  setToDate(e) {
    const dayAfterFromDate = this.getFromDate().add(1, 'day')
    this.toDateInputTarget.setAttribute('min', dayAfterFromDate.format('YYYY-MM-DD'))
    if (this.toDateInputTarget.value == "") {
      this.toDateInputTarget.value = dayAfterFromDate.format('YYYY-MM-DD')
    }
    if (this.getToDate() <= this.getFromDate()) {
      this.toDateInputTarget.value = ""
    }
  }

  setInputValue(input, value) {
    console.log('set input value', input, value)
    input.value = value
  }

  showPricePreview(amount) {
    console.log('showPricePreview', amount)
    this.pricePreviewTarget.innerHTML = (amount / 100) + ' €'
    this.priceCalculationNoticeTarget.classList.add('hidden')
    this.priceDivTarget.classList.remove('hidden')
  }

  hideTierPricing() {
    this.tierPricingTarget.classList.add('hidden')
  }

  showTierPricing() {
    this.tierPricingTarget.classList.remove('hidden')
  }

  toggleLodgingsDiv() {
    if (this.forLodging()) {
      this.divLodgingsTarget.classList.replace('hidden', 'block')
    } else {
      this.divLodgingsTarget.classList.replace('block', 'hidden')
    }
  }

  toggleRoomsDiv() {
    if (this.forLodging()) {
      this.divRoomsTarget.classList.replace('block', 'hidden')
    } else {
      this.divRoomsTarget.classList.replace('hidden', 'block')
    }
  }

  togglePriceDetails() {
    this.togglePriceCalculationNotice()
    this.togglePriceSection()
    this.calculatePrice()
  }

  async calculatePrice() {
    if (this.readyForPriceCalculation()) {
      console.log('calculatePrice...')
      const request = new FetchRequest(
        'post', 
        '/booking_prices', 
        { 
          body: JSON.stringify({ 
          booking: {
            booking_type: (this.forLodging() ? "lodging" : "rooms"),
            lodging_id: this.getSelectedLodgingValue(),
            tier_lodgings: this.getSelectedTierLodgings(),
            tier_rooms: this.getSelectedTierRooms(),
            from_date: this.fromDateInputTarget.value,
            to_date: this.toDateInputTarget.value,
            adults: parseInt(this.adultsInputTarget.value) || 0,
            children: parseInt(this.childrenInputTarget.value) || 0
          }
        }) 
      })
      const response = await request.perform()
      if (response.ok) {
        const body = await response.text
        const amount = JSON.parse(body).amount
        console.log('calculated price', amount)
        this.togglePrice(amount)
      }
    }
  }

  async showSimilarBookings() {
    console.log('showSimilarBookings()')
    fetch("/pages/other_bookings?from_date=" + this.fromDateInputTarget.value + "&to_date=" + this.toDateInputTarget.value)
      .then(response => response.text())
      .then(html => this.otherBookingsTarget.innerHTML = html)
    // const request = new FetchRequest(
    //   'get', 
    //   '/pages/other_bookings', 
    //   { 
    //     body: JSON.stringify({ 
    //       from_date: this.fromDateInputTarget.value,
    //       to_date: this.toDateInputTarget.value
    //     })
    //   }) 
    // const response = await request.perform()
    // if (response.ok) {
    //   console.log('response is ok')
    //   // const body = await response.text
    //   // console.log('body', body)
    //   // const amount = JSON.parse(body).amount
    //   // console.log('calculated price', amount)
    //   // this.togglePrice(amount)
    // }
  }

  togglePrice(amount) {
    if (amount > 0) {
      console.log('amount > 0')
      this.pricePreviewTarget.innerHTML = (amount / 100) + ' €'
      this.setInputValue(this.shownPriceInputTarget, amount)
      this.priceDivTarget.classList.replace('hidden', 'block')
    } else {
      console.log('amount <= 0')
      this.priceDivTarget.classList.replace('block', 'hidden')
    }
  }

  togglePriceCalculationNotice() {
    if (this.readyForPriceCalculation()) {
      this.priceCalculationNoticeTarget.classList.replace('block', 'hidden')
      console.log('readyForPriceCalculation')
    } else {
      this.priceCalculationNoticeTarget.classList.replace('hidden', 'block')
      console.log('!readyForPriceCalculation')
    }
  }

  togglePriceSection() {
    if (this.readyForPriceCalculation()) {
      this.priceSectionTarget.classList.replace('hidden', 'block')
      if (this.forLodging()) {
        this.tierPricingForLodgingsTarget.classList.replace('hidden', 'block')
        this.tierPricingForRoomsTarget.classList.replace('block', 'hidden')
      } else {
        this.tierPricingForLodgingsTarget.classList.replace('block', 'hidden')
        this.tierPricingForRoomsTarget.classList.replace('hidden', 'block')
      }
    } else {
      this.priceSectionTarget.classList.replace('block', 'hidden')
      this.tierPricingForLodgingsTarget.classList.replace('block', 'hidden')
      this.tierPricingForRoomsTarget.classList.replace('block', 'hidden')
    }
  }

  readyForPriceCalculation() {
    if (this.forLodging()) {
      return this.getFromDate().isValid() && this.getToDate().isValid() && this.getPeopleCount() > 0 && this.getSelectedLodging() !== null
    } else {
      return this.getFromDate().isValid() && this.getToDate().isValid() && this.getPeopleCount() > 0
    }
  }

  forLodging() {
    return this.getSelectedBookingType() == 'lodging'
  }

  // show 'Party Hall' section only when available
  togglePartyHallOption() {
    const selectedLodging = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0]
    if (selectedLodging !== undefined) {
      const availability = selectedLodging.dataset.bookingPartyHallAvailabilityParam
      if (availability) {
        this.partyHallOptionTarget.classList.replace('hidden', 'block')
      } else {
        this.partyHallOptionTarget.classList.replace('block', 'hidden')
      }
    }
  }


  // // calculate booking price
  // calculateAmount(nights) {
  //   const adults = parseInt(this.adultsInputTarget.value) || 0
  //   const children = parseInt(this.childrenInputTarget.value) || 0
  //   try {
  //     if (this.bookingTypeFieldTarget.value == 'lodging') {
  //       return this.calculateAmountForLodging(nights, this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0])
  //     } else {
  //       const tierPrice = document.querySelector('.selected-tier').dataset.bookingTierAmountParam
  //       return nights * tierPrice * (adults + children)
  //     }
  //   } catch {
  //     return -1
  //   }
  // }

  // calculateAmountForLodging(nights, lodgingInput) {
  //   const nightPrice = lodgingInput.dataset.bookingPriceNightParam
  //   const weekendDiscount = lodgingInput.dataset.bookingWeekendDiscountParam
  //   const fromDate = moment(this.fromDateInputTarget.value)
  //   const toDate = moment(this.toDateInputTarget.value)
  //   var days = []
  //   for (var m = moment(fromDate); m.isBefore(toDate); m.add(1, 'days')) {
  //     days.push(m.day())
  //   }
  //   // how many weekends? (for the discount)
  //   days = days.filter(day => day == 5 || day == 6);
  //   console.log('days', days)
  //   var amount = nights * nightPrice
  //   const weekendsCount = Math.floor(days.length / 2)
  //   console.log('weekendsCount', weekendsCount)
  //   console.log('weekendDiscount', weekendDiscount)
  //   amount = amount - (weekendsCount * weekendDiscount)
  //   return amount
  // }

  // // user checks one of the lodgings options
  // selectLodging(e) {
  //   this.togglePartyHallSection(e.params.partyHallAvailability)
  //   this.setPrice()
  // }

  // // set booking type
  // setBookingType(e) {
  //   this.setInputValue(this.bookingTypeFieldTarget, e.params.bookingType)
  //   this.drawForm()
  //   // this.toggleTierPricing()
  // }

  // setInputValue(input, value) {
  //   console.log('set input value', input, value)
  //   input.value = value
  // }

  // setPrice() {
  //   const adults = parseInt(this.adultsInputTarget.value) || 0
  //   const children = parseInt(this.childrenInputTarget.value) || 0
  //   const fromDate = moment(this.fromDateInputTarget.value)
  //   const toDate = moment(this.toDateInputTarget.value)
  //   console.log('setPrice', adults, children, fromDate, toDate)
  //   if ((adults == 0 && children == 0) || !fromDate.isValid() || !toDate.isValid()) {
  //     console.log('Sorry, we can\'t preview the price')
  //     this.showPriceCalculationNotice()
  //   } else {
  //     const nights = toDate.diff(fromDate, 'days')
  //     if (nights < 1) {
  //       console.log('Oops, less than one night', nights)
  //       this.showPriceCalculationNotice()
  //     } else {
  //       console.log('All good, we can preview the price')
  //       const amount = this.calculateAmount(nights)
  //       if (amount >= 0) {
  //         this.setInputValue(this.shownPriceInputTarget, amount)
  //         this.showPricePreview(amount)
  //       }
  //     }
  //   }
  // }

  // setSelectedTierCardStyle(activeCard) {
  //   this.tierCardTargets.forEach((el) => {
  //     el.classList.remove('selected-tier')
  //     el.classList.replace('bg-indigo-100', 'bg-white')
  //     el.classList.replace('border-gray-500', 'border-gray-200')
  //   })
  //   activeCard.classList.add('selected-tier')
  //   activeCard.classList.replace('bg-white', 'bg-indigo-100')
  //   activeCard.classList.replace('border-gray-200', 'border-gray-500')
  // }

  // setTier(e) {
  //   const tierName = (e === undefined) ? this.tierInputTarget.value : e.params.tierName
  //   this.setInputValue(this.tierInputTarget, tierName)
  //   const selectedTierCard = (e === undefined) ? document.querySelector('[data-booking-tier-name-param="' + tierName + '"]') : e.currentTarget
  //   this.setSelectedTierCardStyle(selectedTierCard)
  //   this.setTierButton(selectedTierCard.querySelector('.tier-pricing-button'))
  //   this.setPrice()
  // }

  // setTierButton(activeButton) {
  //   this.tierButtonTargets.forEach((el, i) => {
  //     el.classList.replace('bg-indigo-500', 'bg-indigo-50')
  //     el.classList.replace('text-white', 'text-indigo-700')
  //     el.classList.replace('hover:bg-indigo-600', 'hover:bg-indigo-100')
  //     el.innerHTML = 'Sélectionner'
  //   })
  //   activeButton.classList.replace('bg-indigo-50', 'bg-indigo-500')
  //   activeButton.classList.replace('text-indigo-700', 'text-white')
  //   activeButton.classList.replace('hover:bg-indigo-100', 'hover:bg-indigo-600')
  //   activeButton.innerHTML = 'Sélectionné'
  // }

  // // show notice when price can't be calculated
  // showPriceCalculationNotice() {
  //   this.priceCalculationNoticeTarget.classList.remove('hidden')
  //   this.priceDivTarget.classList.add('hidden')
  // }

  // // show price preview
  // showPricePreview(amount) {
  //   this.pricePreviewTarget.innerHTML = (amount / 100) + ' €'
  //   this.priceCalculationNoticeTarget.classList.add('hidden')
  //   this.priceDivTarget.classList.remove('hidden')
  // }

  // // show tier pricing options only for rooms
  // toggleTierPricing() {
  //   if (this.bookingTypeFieldTarget.value == 'lodging') {
  //     this.tierPricingTarget.classList.add('hidden')
  //   } else {
  //     this.tierPricingTarget.classList.remove('hidden')
  //   }
  // }

  // // show 'Party Hall' section only when available
  // togglePartyHallSection(availability) {
  //   if (availability) {
  //     this.partyHallSectionTarget.classList.replace('hidden', 'block')
  //   } else {
  //     this.partyHallSectionTarget.classList.replace('block', 'hidden')
  //   }
  // }
}
