import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'
import moment from "moment"

export default class extends Controller {
  static targets = [
    'stayItems'
  ]

 connect() {
    console.log('connect stays')
  }

  initialize() {
    console.log('initialize stays')
    this.drawForm()
  }

   drawForm(e) {
    
   }

}