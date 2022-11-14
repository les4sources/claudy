import { Controller } from "@hotwired/stimulus"
// import { animations } from '../../animations'

export default class extends Controller {
  static targets = [ 'pastWeeksToggler', 'day', 'week' ]

  initialize() {
    const isCurrent = this.data.get('current')
    if (isCurrent == 'true') {
      this.hidePastWeeks()
    }
  }

  hidePastWeeks() {
    this.weekTargets.forEach((el, i) => {
      if (el.dataset.pastWeek == 'true') {
        el.classList.add('hide')
      }
    })
  }

  redirectToEvent(e) {
    // don't redirect when opening the event dropdown
    if ($(e.target).closest('.inline-icon').data('toggle') == undefined) {
      document.location = $(e.target).closest('.event').data('event-path')
    }
  }

  redirectToBooking(e) {
    // don't redirect when opening the reservation dropdown
    if ($(e.target).closest('.inline-icon').data('toggle') == undefined) {
      document.location = $(e.target).closest('.reservation').data('booking-path')
    }
  }

  showPastWeeks() {
    this.pastWeeksTogglerTarget.classList.add('hide')
    this.weekTargets.forEach((el, i) => {
      el.classList.remove('hide')
    })
    this.dayTargets.forEach((el, i) => {
      el.classList.remove('hide-for-small-only')
    })
    setTimeout(() => {
      // scroll to yesterday, particularly useful on touch screens
      document.querySelector('.today').scrollIntoView()
      window.scrollBy(0,-100)
    }, 500)
  }
}
