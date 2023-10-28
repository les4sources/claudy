import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    'item',
    'week',
    'pastWeeksToggler'
  ]

  connect() {
    console.log('connect dashboard-calendar')
  }

  initialize() {
    console.log('initialize dashboard-calendar')
    const isCurrent = this.data.get('current')
    if (isCurrent == 'true') {
      this.hidePastWeeks()
    }
  }

  hidePastWeeks() {
    console.log('hidePastWeeks')
    this.weekTargets.forEach((el, i) => {
      if (el.dataset.pastWeek == 'true') {
        el.classList.add('hidden')
      }
    })
  }

  clickCalendar(e) {
    // hide popovers
    console.log('click calendar', e.target.dataset.popoverTarget)
    document.querySelectorAll('.popover').forEach((element) => {
      console.log(element.id, e.target.dataset.popoverTarget)
      if (element.id != e.target.dataset.popoverTarget) {
        element.classList.replace('visible', 'invisible')
      }
    })
  }

  showPastWeeks() {
    this.pastWeeksTogglerTarget.classList.add('hidden')
    this.weekTargets.forEach((el, i) => {
      el.classList.remove('hidden')
    })
  }
}
