import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fullContent", 
    "truncatedContent",
    "moreLink"
  ]

  connect() {
    if (this.fullContentTarget.closest('#dashboard-calendar') !== null) {
      this.toggleContent();
    } else {
      this.truncatedContentTarget.classList.add("hidden");
      this.fullContentTarget.classList.remove("hidden");
      this.moreLinkTarget.classList.add("hidden");
    }
  }

  toggleContent() {
    if (this.fullContentTarget.textContent.length > 100) {
      // this.moreLinkTarget.classList.remove("hidden");
    } else {
      this.moreLinkTarget.classList.add("hidden");
      this.truncatedContentTarget.classList.add("hidden");
      this.fullContentTarget.classList.remove("hidden");
    }
  }

  showMore() {
    this.truncatedContentTarget.classList.add("hidden");
    this.moreLinkTarget.classList.add("hidden");
    this.fullContentTarget.classList.remove("hidden");
  }
}
