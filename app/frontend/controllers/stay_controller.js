import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'
import moment from "moment"

export default class extends Controller {
  static targets = [
    'stayItems',
    'customerEmail', 
    'customerFirstname', 
    'customerLastname', 
    'customerPhone',
    'startDateInput',
    'endDateInput',
  
  ]

 connect() {
    console.log('connect stays')
  }

  initialize() {
    console.log('initialize stays')
  }

   drawForm(e) {
    
   }


  async lookupCustomer() {
    const email = this.customerEmailTarget.value

    if (email) {
       fetch("/customers/lookup?email="+email)
        .then(response => response.json())
        .then(data => {
          if (data.found) {
            console.log("data : " + data)
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
    const dayAfterStartDate = this.getStartDate().add(1, 'day')
    this.endDateInputTarget.setAttribute('min', dayAfterStartDate.format('YYYY-MM-DD'))
    if (this.endDateInputTarget.value == "") {
      this.endDateInputTarget.value = dayAfterStartDate.format('YYYY-MM-DD')
    }
    if (this.getEndDate() <= this.getStartDate()) {
      this.endDateInputTarget.value = dayAfterStartDate.format('YYYY-MM-DD')
    }
  }


  async saveStartDate(){
    
      const stayId = this.element.querySelector("#stay_id").value
      console.log("stay_id: "+ stayId)
      const request = new FetchRequest(
        'post', 
        "/stays/"+stayId+"/save_date", 
         { 
          body: JSON.stringify({ 
          stay: {
            start_date: this.getStartDate(),
          }
        }) 
      })
      const response = await request.perform()
      if (response.ok) {
        console.log('start date saved')
      }
  }

  async saveEndDate(){
      const stayId = this.element.querySelector("#stay_id").value
      const request = new FetchRequest(
        'post', 
        "/stays/"+stayId+"/save_date", 
         { 
          body: JSON.stringify({ 
          stay: {
            end_date: this.getEndDate(),
          }
        }) 
      })
      const response = await request.perform()
      if (response.ok) {
        console.log('end date saved')
      }
  }



}