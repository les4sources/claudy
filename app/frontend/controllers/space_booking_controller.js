import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'
import moment from "moment"

export default class extends Controller {
  static targets = [
    'advanceAmountInput',
    'spaceBookingsForDateRange',
    'fromDateInput',
    'priceInput',
    'toDateInput'
  ]

  static values = {
    objectId: Number
  }

  connect() {
    console.log('connect space-booking')
  }

  initialize() {
    console.log('initialize space-booking')
    this.drawForm()
  }

  drawForm(e) {
    this.showSimilarSpaceBookings()
  }

  fillAdvanceAmount() {
    if (this.priceInputTarget.value != '' && this.advanceAmountInputTarget.value == '') {
      this.setInputValue(this.advanceAmountInputTarget, this.priceInputTarget.value / 2)
    }
  }

  getFromDate() {
    return moment(this.fromDateInputTarget.value)
  }

  getToDate() {
    return moment(this.toDateInputTarget.value)
  }

  setInputValue(input, value) {
    console.log('set input value', input, value)
    input.value = value
  }

  setToDate(e) {
    this.toDateInputTarget.setAttribute('min', this.getFromDate().format('YYYY-MM-DD'))
    if (this.toDateInputTarget.value == "" || this.getToDate() < this.getFromDate()) {
      this.toDateInputTarget.value = this.getFromDate().format('YYYY-MM-DD')
    }
    // if (this.getToDate() < this.getFromDate()) {
    //   this.toDateInputTarget.value = ""
    // }
  }

  async showSimilarSpaceBookings() {
    console.log('showSimilarSpaceBookings()', this.objectIdValue)
    if (this.getFromDate().isValid() && this.getToDate().isValid()) {
      console.log('get other space bookings...')
      fetch("/pages/other_space_bookings?space_booking_id=" + this.objectIdValue + "&from_date=" + this.fromDateInputTarget.value + "&to_date=" + this.toDateInputTarget.value)
        .then(response => response.text())
        .then(html => Turbo.renderStreamMessage(html));
    } else {
      console.log('clear space bookings list')
      this.spaceBookingsForDateRangeTarget.innerHTML = ''
    }
  }
}
