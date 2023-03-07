import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'
import moment from "moment"

export default class extends Controller {
  static targets = [
    'spaceBookingsForDateRange',
    'fromDateInput',
    'toDateInput'
  ]

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

  getFromDate() {
    return moment(this.fromDateInputTarget.value)
  }

  getToDate() {
    return moment(this.toDateInputTarget.value)
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

  async showSimilarSpaceBookings() {
    console.log('showSimilarSpaceBookings()')
    if (this.getFromDate().isValid() && this.getToDate().isValid()) {
      console.log('get other space bookings...')
      fetch("/pages/other_space_bookings?from_date=" + this.fromDateInputTarget.value + "&to_date=" + this.toDateInputTarget.value)
        .then(response => response.text())
        .then(html => Turbo.renderStreamMessage(html));
    } else {
      console.log('clear space bookings list')
      this.spaceBookingsForDateRangeTarget.innerHTML = ''
    }
  }
}
