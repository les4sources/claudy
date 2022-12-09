import { Controller } from "@hotwired/stimulus"

// TODO: for lodgings, 2 nights max (weekend), 1 night for weekdays
// TODO: check availability
// TODO: prepare form when page is loaded
  // Toggle partyHallSection
  // Toggle payment details

export default class extends Controller {
  static targets = [
    'bookingTypeField',
    'partyHallSection'
  ]

  initialize() {
    console.log('Controller: booking')
  }

  setBookingType(e) {
    this.bookingTypeFieldTarget.value = e.params.bookingType
  }

  togglePartyHallSection(e) {
    if (e.params.partyHallAvailability) {
      this.partyHallSectionTarget.classList.replace('hidden', 'block')
    } else {
      this.partyHallSectionTarget.classList.replace('block', 'hidden')
    }
  }
}
