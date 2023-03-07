import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    'item'
  ]

  connect() {
    console.log('connect dashboard-calendar')
  }

  initialize() {
    console.log('initialize dashboard-calendar')
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
}
