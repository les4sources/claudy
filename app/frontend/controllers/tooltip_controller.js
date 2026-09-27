import { Controller } from "@hotwired/stimulus"
import { createPopper } from "@popperjs/core"

// Two modes.
//
// 1. Target mode — replaces Flowbite `data-tooltip-target`:
//   el(data-controller="tooltip"
//      data-action="mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide"
//      data-tooltip-target-value="tooltip-human-42"
//      data-tooltip-placement-value="top")
//
//   The tooltip element (by id) is expected to carry Tailwind classes
//   'invisible opacity-0' when hidden (matches the existing `_tooltips.html.slim` partials).
//
// 2. Text mode (epic #330, phase 6) — la bulle est construite ici, en Tailwind
//    pur, sans Popper : bulle sombre arrondie avec sa flèche, au-dessus de
//    l'élément ou en dessous s'il n'y a pas la place (première ligne d'une
//    liste), recalée dans la largeur de la fenêtre. Posée en `fixed` sur le
//    <body> : aucun décalage de mise en page, jamais rognée par un parent.
//    Côté vue, passer par le helper `tooltip_options` (UiHelper), qui pose aussi
//    l'`aria-label` à la place du `title=` natif.
//   el(data-controller="tooltip"
//      data-action="mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide click->tooltip#hide"
//      data-tooltip-text-value="Modifier")
const GAP = 8     // entre l'élément et la bulle
const MARGIN = 4  // marge minimale au bord de la fenêtre

export default class extends Controller {
  static values = {
    target: String,
    text: String,
    placement: { type: String, default: "top" },
  }

  connect() {
    this.tooltipEl = this.textValue ? null : document.getElementById(this.targetValue)
    this.popper = null
    this.bubble = null
    this.onScroll = () => this.hide()
  }

  disconnect() {
    this.hide()
    this.bubble = null
    this.tooltipEl = null
  }

  show() {
    if (this.textValue) return this.showBubble()
    if (!this.tooltipEl) return
    if (!this.popper) {
      this.popper = createPopper(this.element, this.tooltipEl, {
        placement: this.placementValue,
        modifiers: [{ name: "offset", options: { offset: [0, 8] } }],
      })
    } else {
      this.popper.update()
    }
    this.tooltipEl.classList.remove("invisible", "opacity-0")
    this.tooltipEl.classList.add("visible", "opacity-100")
  }

  hide() {
    if (this.bubble) return this.hideBubble()
    if (!this.tooltipEl) return
    this.tooltipEl.classList.remove("visible", "opacity-100")
    this.tooltipEl.classList.add("invisible", "opacity-0")
    if (this.popper) {
      this.popper.destroy()
      this.popper = null
    }
  }

  // --- Text mode -----------------------------------------------------------

  showBubble() {
    if (!this.bubble) this.bubble = this.buildBubble()
    this.bubble.firstChild.textContent = this.textValue
    document.body.appendChild(this.bubble)
    this.positionBubble()
    requestAnimationFrame(() => this.bubble?.classList.replace("opacity-0", "opacity-100"))
    // Une bulle `fixed` ne suit pas le défilement : on la retire plutôt que de
    // la laisser flotter loin de son icône.
    window.addEventListener("scroll", this.onScroll, { capture: true, passive: true })
  }

  hideBubble() {
    window.removeEventListener("scroll", this.onScroll, { capture: true })
    this.bubble.classList.replace("opacity-100", "opacity-0")
    this.bubble.remove()
  }

  buildBubble() {
    const bubble = document.createElement("div")
    bubble.setAttribute("aria-hidden", "true") // l'élément porte déjà son aria-label
    bubble.className = "pointer-events-none fixed left-0 top-0 z-50 w-max max-w-xs rounded-md bg-gray-900 px-2 py-1 text-xs font-medium leading-snug text-white shadow-lg opacity-0 transition-opacity duration-100"
    const label = document.createElement("span")
    label.className = "relative"
    const arrow = document.createElement("span")
    arrow.className = "absolute h-2 w-2 rotate-45 bg-gray-900"
    bubble.append(label, arrow)
    return bubble
  }

  positionBubble() {
    const bubble = this.bubble
    const arrow = bubble.lastChild
    bubble.style.left = "0px"
    bubble.style.top = "0px"

    const rect = this.element.getBoundingClientRect()
    const width = bubble.offsetWidth
    const height = bubble.offsetHeight
    const viewportWidth = document.documentElement.clientWidth
    const viewportHeight = document.documentElement.clientHeight

    const fitsAbove = rect.top - GAP - height >= MARGIN
    const fitsBelow = rect.bottom + GAP + height <= viewportHeight - MARGIN
    const above = this.placementValue === "bottom" ? !fitsBelow && fitsAbove : fitsAbove || !fitsBelow

    const center = rect.left + rect.width / 2
    const left = Math.min(Math.max(center - width / 2, MARGIN), viewportWidth - width - MARGIN)
    const top = above ? rect.top - GAP - height : rect.bottom + GAP

    bubble.style.left = `${Math.round(left)}px`
    bubble.style.top = `${Math.round(top)}px`

    // La flèche pointe toujours le centre de l'élément, même bulle recalée.
    arrow.style.left = `${Math.round(Math.min(Math.max(center - left - 4, 6), width - 14))}px`
    arrow.style.top = above ? "" : "-4px"
    arrow.style.bottom = above ? "-4px" : ""
  }
}
