import { Controller } from "@hotwired/stimulus"

// Le menu de droite d'une section du Guide (Michael, 2026-11-12) suit la
// lecture : le chapitre dont le titre est passé sous le haut de l'écran est
// allumé dans le menu (`aria-current`).
//
//   div(data-controller="guide-toc")
//     article(id="chapitre-12" data-guide-toc-target="section")
//     a(href="#chapitre-12" data-guide-toc-target="link")
export default class extends Controller {
  static targets = ["section", "link"]

  connect() {
    this.onScroll = () => {
      if (this.frame) return
      this.frame = requestAnimationFrame(() => {
        this.frame = null
        this.highlight()
      })
    }
    // `capture` : la page défile dans la fenêtre ou dans un conteneur.
    document.addEventListener("scroll", this.onScroll, { passive: true, capture: true })
    this.highlight()
  }

  disconnect() {
    document.removeEventListener("scroll", this.onScroll, { capture: true })
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  highlight() {
    if (this.sectionTargets.length === 0) return
    const line = Math.min(160, window.innerHeight / 3)
    let active = this.sectionTargets[0]
    for (const section of this.sectionTargets) {
      if (section.getBoundingClientRect().top <= line) active = section
    }
    // Tout en bas de la page, le dernier chapitre court n'atteint jamais la ligne.
    const root = document.scrollingElement
    if (root && root.scrollTop + window.innerHeight >= root.scrollHeight - 4) {
      active = this.sectionTargets[this.sectionTargets.length - 1]
    }
    this.linkTargets.forEach((link) => {
      if (link.getAttribute("href") === `#${active.id}`) link.setAttribute("aria-current", "location")
      else link.removeAttribute("aria-current")
    })
  }
}
