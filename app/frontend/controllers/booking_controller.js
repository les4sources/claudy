import { Controller } from "@hotwired/stimulus"
import moment from "moment"

// TODO: for lodgings, 2 nights max (weekend), 1 night for weekdays
// TODO: check availability
// TODO: prepare form when page is loaded
  // Toggle partyHallSection
  // Toggle payment details

export default class extends Controller {
  static targets = [
    'adultsInput',
    'bookingTypeField',
    'childrenInput',
    'fromDateInput',
    'lodgingRadioButton',
    'partyHallSection',
    'priceCalculationNotice',
    'priceDiv',
    'pricePreview',
    'shownPriceInput',
    'tierButton',
    'tierCard',
    'tierPricing',
    'tierInput',
    'toDateInput'
  ]

  initialize() {
    console.log('Controller: booking')
  }

  // calculate booking price
  calculateAmount(nights) {
    const adults = parseInt(this.adultsInputTarget.value) || 0
    const children = parseInt(this.childrenInputTarget.value) || 0
    if (this.bookingTypeFieldTarget.value == 'lodging') {
      const nightPrice = this.lodgingRadioButtonTargets.filter(radio => radio.checked)[0].dataset.bookingPriceNightParam
      return nights * nightPrice
    } else {
      const tierPrice = document.querySelector('.selected-tier').dataset.bookingTierAmountParam
      return nights * tierPrice * (adults + children)
    }
  }

  // user checks one of the lodgings options
  selectLodging(e) {
    this.togglePartyHallSection(e)
    this.setPrice()
  }

  // set booking type
  setBookingType(e) {
    this.setInputValue(this.bookingTypeFieldTarget, e.params.bookingType)
    this.toggleTierPricing()
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
      if (nights < 1) {
        console.log('Oops, less than one night', nights)
        this.showPriceCalculationNotice()
      } else {
        console.log('All good, we can preview the price')
        const amount = this.calculateAmount(nights)
        this.setInputValue(this.shownPriceInputTarget, amount)
        this.showPricePreview(amount)
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
    this.setInputValue(this.tierInputTarget, e.params.tierName)
    this.setSelectedTierCardStyle(e.currentTarget)
    this.setTierButton(e.currentTarget.querySelector('.tier-pricing-button'))
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

  // show notice when price can't be calculated
  showPriceCalculationNotice() {
    this.priceCalculationNoticeTarget.classList.remove('hidden')
    this.priceDivTarget.classList.add('hidden')
  }

  // show price preview
  showPricePreview(amount) {
    this.pricePreviewTarget.innerHTML = (amount / 100) + ' €'
    this.priceCalculationNoticeTarget.classList.add('hidden')
    this.priceDivTarget.classList.remove('hidden')
  }

  // show tier pricing options only for rooms
  toggleTierPricing() {
    if (this.bookingTypeFieldTarget.value == 'lodging') {
      this.tierPricingTarget.classList.add('hidden')
    } else {
      this.tierPricingTarget.classList.remove('hidden')
    }
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
