import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'
import moment from "moment"

export default class extends Controller {
  static values = {
    id: Number
  }

  static targets = [
    'stayItems',
    'customerEmail', 
    'customerFirstname', 
    'customerLastname', 
    'customerPhone',
    'startDateInput',
    'endDateInput',
    'staysForDateRange'
  ]

  connect() {
    console.log('connect stays', this.idValue)
  }

  initialize() {
    console.log('initialize stays')
  }

  drawForm(e) {
    this.showSimilarStays()
  }

  async lookupCustomer() {
    console.log('lookupCustomer')
    const email = this.customerEmailTarget.value

    if (email) {
       fetch("/customers/lookup?email="+email)
        .then(response => response.json())
        .then(data => {
          if (data.found) {
            console.log("data : ", data)
            this.customerFirstnameTarget.value = data.firstname
            this.customerLastnameTarget.value = data.lastname
            this.customerPhoneTarget.value = data.phone
          } else {
            console.log("No customer found with that email")
          }
        })
    }
  }

  getStartDate() {
    return moment(this.startDateInputTarget.value)
  }

   getEndDate() {
    return moment(this.endDateInputTarget.value)
  }

  setEndDate() {
    console.log('setEndDate')
    const dayAfterStartDate = this.getStartDate().add(1, 'day')
    this.endDateInputTarget.setAttribute('min', dayAfterStartDate.format('YYYY-MM-DD'))
    if (this.endDateInputTarget.value == "") {
      this.endDateInputTarget.value = dayAfterStartDate.format('YYYY-MM-DD')
    }
    if (this.getEndDate() <= this.getStartDate()) {
      this.endDateInputTarget.value = dayAfterStartDate.format('YYYY-MM-DD')
    }
  }

  async saveDates() {
    console.log('saveDates')
    const request = new FetchRequest(
      'post', 
      "/stays/"+this.idValue+"/save_dates", 
       { 
        body: JSON.stringify({ 
        stay: {
          start_date: this.getStartDate(),
          end_date: this.getEndDate(),
        }
      }) 
    })
    const response = await request.perform()
    if (response.ok) {
      //console.log('end date saved')
    }
  }

  async showSimilarStays() {
    if (this.getStartDate().isValid() && this.getEndDate().isValid()) {
      console.log('get other stays...' + this.idValue)
      fetch("/pages/other_stays?stay_id=" + this.idValue + "&start_date=" + this.startDateInputTarget.value + "&end_date=" + this.endDateInputTarget.value)
        .then(response => response.text())
        .then(html => Turbo.renderStreamMessage(html));
    } else {
      console.log('clear bookings list')
      this.staysForDateRangeTarget.innerHTML = ''
    }
  }



}