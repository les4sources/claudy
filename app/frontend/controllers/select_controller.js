import { Controller } from "@hotwired/stimulus";
import $ from "jquery";


import select2 from "select2"


export default class extends Controller {
  static targets = ["select"];

  connect() {
   // console.log('connect select');
   // $(this.selectTarget).select2();
  }
}