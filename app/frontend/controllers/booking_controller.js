import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'
import moment from "moment"

export default class extends Controller {
  static targets = [
    'bookingTypeOptions',
    'bookingsForDateRange',
    'divLodgings',
    'divRooms',
    'fromDateInput',
    'lodgingsPanel',
    'lodgingRadioButton',
    'partyHallOption',
    'priceInput',
    'roomsPanel',
    'toDateInput'
  ]

  static values = {
    objectId: Number
  }

  connect() {
    console.log('connect booking')
  }

  initialize() {
    console.log('initialize booking', this.getSelectedBookingType())
    this.drawForm()
  }

  drawForm(e) {
    this.toggleLodgingsDiv()
    this.toggleRoomsDiv()
    this.togglePartyHallOption()
    this.showSimilarBookings()
  }

  getFromDate() {
    return moment(this.fromDateInputTarget.value)
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
      this.toDateInputTarget.value = dayAfterFromDate.format('YYYY-MM-DD')
    }
  }

  setInputValue(input, value) {
    console.log('set input value', input, value)
    input.value = value
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

  async showSimilarBookings() {
    console.log('showSimilarBookings()')
    if (this.getFromDate().isValid() && this.getToDate().isValid()) {
      console.log('get other bookings...')
      fetch("/pages/other_bookings?booking_id=" + this.objectIdValue + "&from_date=" + this.fromDateInputTarget.value + "&to_date=" + this.toDateInputTarget.value)
        .then(response => response.text())
        .then(html => Turbo.renderStreamMessage(html));
    } else {
      console.log('clear bookings list')
      this.bookingsForDateRangeTarget.innerHTML = ''
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
}
