import { Controller } from "@hotwired/stimulus"
import moment from "moment"

// TODO: check availability
// TODO: prepare form when page is loaded
  // Toggle payment details

export default class extends Controller {
  static targets = [
    'adultsInput',
    'bookingTypeOptions',
    'childrenInput',
    'fromDateInput',
    'lodgingsPanel',
    'lodgingRadioButton',
    'partyHallSection',
    'priceCalculationNotice',
    'priceDiv',
    'pricePreview',
    'roomsPanel',
    'shownPriceInput',
    'tierButton',
    'tierCard',
    'tierPricing',
    'tierInput',
    'toDateInput'
  ]

  connect() {
    console.log('connect booking')
  }

  initialize() {
    console.log('Controller: booking', this.getSelectedBookingType())
    // initialize form
    if (this.getSelectedBookingType() == 'lodging') {
      this.showLodgingsPanel()
      // hide tier pricing
      this.hideTierPricing()
      this.setPrice()
      // toggle 'party hall' section if Grand-Duc checked
      const selectedLodging = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0]
      if (selectedLodging !== undefined) {
        this.togglePartyHallSection(selectedLodging.dataset.bookingPartyHallAvailabilityParam)
      }
    } else {
      this.showRoomsPanel()
      this.showTierPricing()
      // this.roomsTabTarget.click()
      console.log('this.tierInputTarget.value', this.tierInputTarget.value)
      if (this.tierInputTarget.value !== undefined && this.tierInputTarget.value != 'undefined') {
        this.setTier()
      } else {
        this.showPriceCalculationNotice()
      }
    }
  }

  // calculate booking price
  calculateAmount(nights) {
    const adults = parseInt(this.adultsInputTarget.value) || 0
    const children = parseInt(this.childrenInputTarget.value) || 0
    console.log('adults, children, bookingType', adults, children, this.getSelectedBookingType())
    try {
      if (this.getSelectedBookingType() == 'lodging') {
        // const nightPrice = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0].dataset.bookingPriceNightParam
        return this.calculateAmountForLodging(nights, this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0])
        // console.log('nightPrice', nightPrice)
        // return nights * nightPrice
      } else {
        const tierPrice = document.querySelector('.selected-tier').dataset.bookingTierAmountParam
        console.log('tierPrice', tierPrice)
        return nights * tierPrice * (adults + children)
      }
    } catch {
      return -1
    }
  }

  calculateAmountForLodging(nights, lodgingInput) {
    const nightPrice = lodgingInput.dataset.bookingPriceNightParam
    const weekendDiscount = lodgingInput.dataset.bookingWeekendDiscountParam
    const fromDate = moment(this.fromDateInputTarget.value)
    const toDate = moment(this.toDateInputTarget.value)
    var days = []
    for (var m = moment(fromDate); m.isBefore(toDate); m.add(1, 'days')) {
      days.push(m.day())
    }
    // how many weekends? (for the discount)
    days = days.filter(day => day == 5 || day == 6);
    console.log('days', days)
    var amount = nights * nightPrice
    const weekendsCount = Math.floor(days.length / 2)
    console.log('weekendsCount', weekendsCount)
    console.log('weekendDiscount', weekendDiscount)
    amount = amount - (weekendsCount * weekendDiscount)
    return amount
  }

  getSelectedBookingType() {
    return this.bookingTypeOptionsTargets.find(button => button.checked).value
  }

  // user clicks one of the booking options
  selectBookingTypeOption(e) {
    console.log('selectBookingTypeOption')
    this.initialize()
    // if (this.getSelectedBookingType() == "lodging") {
    //   // hide tier pricing
    //   this.toggleTierPricing()
    //   this.setPrice()
    //   // toggle 'party hall' section if Grand-Duc checked
    //   const selectedLodging = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0]
    //   if (selectedLodging !== undefined) {
    //     this.togglePartyHallSection(selectedLodging.dataset.bookingPartyHallAvailabilityParam)
    //   }      
    // } else {

    // }
    // const clickedRadio = (e.target == '') ? e : e.target
    // this.bookingTypeOptionsTargets.forEach((el, i) => {
    //   el.classList.toggle("bg-blue-200", clickedRadio == el )
    // })
    // this.bookingTypeFieldTarget.value = clickedRadio.dataset.bookingLodgingTypeParam
  }

  // user checks one of the lodgings options
  selectLodging(e) {
    this.togglePartyHallSection(e.target.dataset.bookingPartyHallAvailabilityParam)
    this.setPrice()
  }

  setFromDate(e) {
    const dayAfterFromDate = moment(this.fromDateInputTarget.value).add(1, 'day')
    this.toDateInputTarget.setAttribute('min', dayAfterFromDate.format('YYYY-MM-DD'))
    if (this.toDateInputTarget.value == "") {
      this.toDateInputTarget.value = dayAfterFromDate.format('YYYY-MM-DD')
    }
    if (this.toDateInputTarget.value <= this.fromDateInputTarget.value) {
      this.toDateInputTarget.value = ""
    }
  }

  setInputValue(input, value) {
    console.log('set input value', input, value)
    input.value = value
  }

  setPrice() {
    const adults = parseInt(this.adultsInputTarget.value) || 0
    const children = parseInt(this.childrenInputTarget.value) || 0
    const fromDate = moment(this.fromDateInputTarget.value)
    const toDate = moment(this.toDateInputTarget.value)
    console.log('setPrice', adults, children, fromDate, toDate)
    if ((adults == 0 && children == 0) || !fromDate.isValid() || !toDate.isValid()) {
      console.log('Sorry, we can\'t preview the price')
      this.showPriceCalculationNotice()
    } else {
      const nights = toDate.diff(fromDate, 'days')
      console.log('toDate and fromDate', toDate, fromDate)
      if (nights < 1) {
        console.log('Oops, less than one night', nights)
        this.showPriceCalculationNotice()
      } else {
        const amount = this.calculateAmount(nights)
        console.log('All good, we can preview the price', amount, nights)
        if (amount >= 0) {
          this.setInputValue(this.shownPriceInputTarget, amount)
          this.showPricePreview(amount)
        }
      }
    }
  }

  setSelectedTierCardStyle(activeCard) {
    this.tierCardTargets.forEach((el) => {
      el.classList.remove('selected-tier')
      el.classList.replace('bg-indigo-100', 'bg-white')
      el.classList.replace('border-gray-500', 'border-gray-200')
    })
    activeCard.classList.add('selected-tier')
    activeCard.classList.replace('bg-white', 'bg-indigo-100')
    activeCard.classList.replace('border-gray-200', 'border-gray-500')
  }

  setTier(e) {
    console.log('setTier()')
    const tierName = (e === undefined) ? this.tierInputTarget.value : e.params.tierName
    this.setInputValue(this.tierInputTarget, tierName)
    const selectedTierCard = (e === undefined) ? document.querySelector('[data-booking-tier-name-param="' + tierName + '"]') : e.currentTarget
    this.setSelectedTierCardStyle(selectedTierCard)
    this.setTierButton(selectedTierCard.querySelector('.tier-pricing-button'))
    this.setPrice()
  }

  setTierButton(activeButton) {
    this.tierButtonTargets.forEach((el, i) => {
      el.classList.replace('bg-indigo-500', 'bg-indigo-50')
      el.classList.replace('text-white', 'text-indigo-700')
      el.classList.replace('hover:bg-indigo-600', 'hover:bg-indigo-100')
      el.innerHTML = 'Sélectionner'
    })
    activeButton.classList.replace('bg-indigo-50', 'bg-indigo-500')
    activeButton.classList.replace('text-indigo-700', 'text-white')
    activeButton.classList.replace('hover:bg-indigo-100', 'hover:bg-indigo-600')
    activeButton.innerHTML = 'Sélectionné'
  }

  showLodgingsPanel() {
    this.roomsPanelTarget.classList.add('hidden')
    this.lodgingsPanelTarget.classList.remove('hidden')
  }

  showRoomsPanel() {
    this.lodgingsPanelTarget.classList.add('hidden')
    this.roomsPanelTarget.classList.remove('hidden')
  }

  // show notice when price can't be calculated
  showPriceCalculationNotice() {
    this.priceCalculationNoticeTarget.classList.remove('hidden')
    this.priceDivTarget.classList.add('hidden')
  }

  // show price preview
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

  // show 'Party Hall' section only when available
  togglePartyHallSection(availability) {
    if (availability) {
      this.partyHallSectionTarget.classList.replace('hidden', 'block')
    } else {
      this.partyHallSectionTarget.classList.replace('block', 'hidden')
    }
  }
}
