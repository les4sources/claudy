import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from '@rails/request.js'

export default class extends Controller {
  static targets = [
    'itemType',
    'productSelection',
    'productQuantity',
    'productPrice',
    'experienceSelection',
    'experienceStartDate',
    'experienceAdultCount',
    'experienceChildrenCount',
    'experienceDuration',
    'experiencePrice',
    'rentalItemSelection',
    'rentalItemQuantity',
    'rentalItemStartDate',
    'rentalItemEndDate',
    'rentalItemPrice',
    'spaceSelection',
    'spaceStartDate',
    'spaceDuration',
    'spacePrice' 
  ]

 connect() {
    console.log('connect stay items')
  }

  initialize() {
    console.log('initialize stay items')
  }


  clickProductPrice(event){
    event.preventDefault()
    this.calculateProductPrice()
  }

  clickExperiencePrice(event){
    event.preventDefault()
    this.calculateExperiencePrice()
  }


  clickRentalItemPrice(event){
    event.preventDefault()
    this.calculateRentalItemPrice()
  }

  clickSpacePrice(event){
    event.preventDefault()
    this.calculateSpacePrice()
  }


  // calculate the price of the given product 
  async calculateProductPrice(){

    let selectedProductId = null;
    this.productSelectionTargets.forEach((radio) => {
      if (radio.checked) {
        selectedProductId = radio.value;
      }
    });

    fetch("/stay_prices/calculate_item_price?item_type="+this.itemTypeTarget.value +"&item_id=" +selectedProductId + "&quantity="+this.productQuantityTarget.value)
        .then(response => response.json())
        .then(data => this.productPriceTarget.value = data.amount);

    }

    // calculate the price of the given experience 
    async calculateExperiencePrice(targetInput){

      let selectedExperienceId = null;
      this.experienceSelectionTargets.forEach((radio) => {
        if (radio.checked) {
          selectedExperienceId = radio.value;
        }
      });

      let paramsStr = "?item_type="+this.itemTypeTarget.value + 
                      "&item_id=" +selectedExperienceId +
                      "&start_date="+this.experienceStartDateTarget.value +
                      "&adult_count="+this.experienceAdultCountTarget.value +
                      "&children_count="+this.experienceChildrenCountTarget.value +
                      "&duration="+this.experienceDurationTarget.value

      fetch("/stay_prices/calculate_item_price"+paramsStr)
          .then(response => response.json())
          .then(data => this.experiencePriceTarget.value = data.amount);

    }


    // calculate the price of the given rental item 
    async calculateRentalItemPrice(){

      let selectedItemId = null;
      this.rentalItemSelectionTargets.forEach((radio) => {
        if (radio.checked) {
          selectedItemId = radio.value;
        }
      });

       let paramsStr = "?item_type="+this.itemTypeTarget.value + 
                      "&item_id=" +selectedItemId +
                      "&start_date="+this.rentalItemStartDateTarget.value +
                      "&end_date="+this.rentalItemEndDateTarget.value +
                      "&quantity="+this.rentalItemQuantityTarget.value

      fetch("/stay_prices/calculate_item_price"+paramsStr)
          .then(response => response.json())
          .then(data => this.rentalItemPriceTarget.value = data.amount);

    }

    // calculate the price of the given space
    async calculateSpacePrice(){

      let selectedItemId = null;
      this.spaceSelectionTargets.forEach((radio) => {
        if (radio.checked) {
          selectedItemId = radio.value;
        }
      });

      let selectedDuration = null;
      this.spaceDurationTargets.forEach((radio) => {
        if (radio.checked) {
          selectedDuration = radio.value;
        }
      });

       let paramsStr = "?item_type="+this.itemTypeTarget.value + 
                      "&item_id=" +selectedItemId +
                      "&start_date="+this.spacetartDateTarget.value +
                      "&duration="+selectedDuration

      fetch("/stay_prices/calculate_item_price"+paramsStr)
          .then(response => response.json())
          .then(data => this.spacePriceTarget.value = data.amount);

    }

}