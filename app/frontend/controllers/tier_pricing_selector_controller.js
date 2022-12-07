import { Controller } from "@hotwired/stimulus"
import moment from "moment"

export default class extends Controller {
  static targets = [
    'adultsInput',
    'button',
    'childrenInput',
    'fromDateInput',
    'notice',
    'price',
    'priceDiv',
    'tierInput',
    'toDateInput'
  ]

  connect() {
    console.log('Controller: tier-pricing-selector', moment)
  }

  setTier(e) {
    this.tierInputTarget.value = e.params.tierName
    this.setTierButton(e.currentTarget.querySelector('.tier-pricing-button'))
    this.setPrice(e.params.amount)
  }

  setTierButton(activeButton) {
    this.buttonTargets.forEach((el, i) => {
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

  setPrice(tierPrice) {
    const adults = parseInt(this.adultsInputTarget.value) || 0
    const children = parseInt(this.childrenInputTarget.value) || 0
    const fromDate = moment(this.fromDateInputTarget.value)
    const toDate = moment(this.toDateInputTarget.value)
    console.log(tierPrice, adults, children, fromDate, toDate)
    if ((adults == 0 && children == 0) || !fromDate.isValid() || !toDate.isValid()) {
      this.noticeTarget.classList.remove('hidden')
      this.priceDivTarget.classList.add('hidden')
    } else {
      this.noticeTarget.classList.add('hidden')
      this.priceDivTarget.classList.remove('hidden')
      const nights = toDate.diff(fromDate, 'days')
      const amount = nights * tierPrice * (adults + children)
      this.priceTarget.innerHTML = amount + ' €'
    }
  }
}
