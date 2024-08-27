import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'

export default class extends Controller {
  static targets = [
    "experienceStartDate"
  ]

 connect() {
    console.log('connect stay items')
  }

  initialize() {
    console.log('initialize stay items')
  }

}