import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'
import moment from "moment"

export default class extends Controller {
  static targets = [
    'stayItems',
    'customerEmail', 
    'customerFirstname', 
    'customerLastname', 
    'customerPhone'
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


}