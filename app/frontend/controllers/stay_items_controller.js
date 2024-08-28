import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'

export default class extends Controller {
  static targets = [
    'itemType',
    'productSelection',
    'productQuantity',
    'productPrice'
  ]

 connect() {
    console.log('connect stay items')
  }

  initialize() {
    console.log('initialize stay items')
  }


  clickProductPrice(event){
    event.preventDefault()
    this.calculatePrice()
  }

  async calculatePrice(){

    let selectedProductId = null;
    this.productSelectionTargets.forEach((radio) => {
      if (radio.checked) {
        selectedProductId = radio.value;
      }
    });

    fetch("/stay_prices/calculate_item_price?item_type="+this.itemTypeTarget.value +"&product_id=" +selectedProductId + "&quantity="+this.productQuantityTarget.value)
        .then(response => response.json())
        .then(data => this.productPriceTarget.value = data.amount);

    }

}