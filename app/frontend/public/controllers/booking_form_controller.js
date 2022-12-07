import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = []

  initialize() {
    console.log('initialize booking form')
  }
}
