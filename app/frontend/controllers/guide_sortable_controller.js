import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Ranger le sommaire du Guide au glisser-déposer (rédacteurs seulement) : les
// chapitres entre eux, et les pages dans un chapitre ou d'un chapitre à
// l'autre. Chaque dépôt envoie le nouvel ordre au serveur.
//
//   div(data-controller="guide-sortable" data-guide-sortable-url-value="/guide/chapters/reorder")
//     section(data-guide-sortable-target="chapter" data-id="3")
//       button(data-guide-sortable-handle="chapter")
//       ul(data-guide-sortable-target="pages" data-url="/guide/chapters/3/reorder_pages")
//         li(data-id="12") button(data-guide-sortable-handle="page")
export default class extends Controller {
  static targets = ["chapter", "pages"]
  static values = { url: String }

  connect() {
    this.sortables = [
      Sortable.create(this.element, {
        handle: "[data-guide-sortable-handle='chapter']",
        draggable: "[data-guide-sortable-target='chapter']",
        animation: 150,
        ghostClass: "opacity-40",
        onEnd: () => this.save(this.urlValue, this.chapterTargets),
      }),
      ...this.pagesTargets.map((list) =>
        Sortable.create(list, {
          group: "guide-pages",
          handle: "[data-guide-sortable-handle='page']",
          draggable: "li[data-id]",
          animation: 150,
          ghostClass: "opacity-40",
          onEnd: (event) => {
            new Set([event.from, event.to]).forEach((pages) => {
              this.save(pages.dataset.url, pages.querySelectorAll("li[data-id]"))
              this.toggleEmpty(pages)
            })
          },
        })
      ),
    ]
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy())
    this.sortables = []
  }

  save(url, elements) {
    const ids = Array.from(elements).map((element) => element.dataset.id)
    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
      },
      body: JSON.stringify({ ids }),
    })
  }

  toggleEmpty(pages) {
    const empty = pages.querySelector("[data-guide-sortable-empty]")
    if (empty) empty.hidden = pages.querySelector("li[data-id]") !== null
  }
}
