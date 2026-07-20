import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    'item',
    'week',
    'cycleBanner',
    'pastWeeksToggler'
  ]

  initialize() {
    const isCurrent = this.data.get('current')
    if (isCurrent == 'true') {
      this.hidePastWeeks()
    }
  }

  hidePastWeeks() {
    this.weekTargets.forEach((el, i) => {
      if (el.dataset.pastWeek == 'true') {
        el.classList.add('hidden')
      }
    })
    this.cycleBannerTargets.forEach((el) => {
      if (el.dataset.pastWeek == 'true') {
        el.classList.add('hidden')
      }
    })
  }

  clickCalendar(e) {
    // hide popovers
    document.querySelectorAll('.popover').forEach((element) => {
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
    this.cycleBannerTargets.forEach((el) => {
      el.classList.remove('hidden')
    })
    this.element.querySelectorAll('[data-past-day-collapsible="true"]').forEach((el) => {
      el.classList.remove('max-md:hidden')
    })
  }
}
