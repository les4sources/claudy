import { Controller } from "@hotwired/stimulus"

// Célébration d'une action « Fait » sur la page de clôture : la ligne
// s'illumine, le bouton se change en coche dessinée, une poignée de
// particules s'envole, le libellé se barre — puis le formulaire part
// réellement et Turbo remplace le bloc du membre.
//
// Posé sur la <li> de l'action ; le bouton « Fait » déclare
// `data-action="click->celebrate#fire"`.
export default class extends Controller {
  static targets = ["label", "button"]
  static values = { duration: { type: Number, default: 780 } }

  fire(event) {
    if (this.fired) return
    event.preventDefault()
    this.fired = true

    const form = event.currentTarget.closest("form")
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    if (reduced) {
      form.requestSubmit()
      return
    }

    this.element.classList.add("is-celebrating")
    this.buildBurst(event.currentTarget)

    setTimeout(() => form.requestSubmit(), this.durationValue)
  }

  // Douze particules aux vecteurs légèrement aléatoires, dans les deux
  // couleurs du bilan (teal + ambre), pour un jet organique plutôt qu'une
  // rosace mécanique.
  buildBurst(anchor) {
    const burst = document.createElement("span")
    burst.className = "celebrate-burst"
    const count = 12
    for (let i = 0; i < count; i++) {
      const dot = document.createElement("i")
      const angle = (i / count) * Math.PI * 2 + (Math.random() - 0.5) * 0.6
      const dist = 22 + Math.random() * 22
      dot.style.setProperty("--px", `${Math.cos(angle) * dist}px`)
      dot.style.setProperty("--py", `${Math.sin(angle) * dist - 6}px`)
      dot.style.setProperty("--pdelay", `${Math.random() * 60}ms`)
      dot.style.setProperty("--psize", (0.7 + Math.random() * 0.9).toFixed(2))
      if (i % 3 === 0) dot.classList.add("is-amber")
      burst.appendChild(dot)
    }
    anchor.appendChild(burst)
  }
}
