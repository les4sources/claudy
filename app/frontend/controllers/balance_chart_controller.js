import { Controller } from "@hotwired/stimulus"

// L'info au survol de la courbe de trésorerie (Michael, 2026-10-14).
//
// Les cercles de la projection sont trop serrés pour être visés un par un :
// le contrôleur suit la souris et prend le point le plus proche en abscisse,
// puis dit sa date, son solde et les mouvements du jour (séjour qui rentre,
// facture ou charge fixe qui sort). Même bulle sombre que `tooltip` en mode
// texte, posée en `fixed` sur le <body> pour n'être jamais rognée.
//
//   div(data-controller="balance-chart"
//       data-balance-chart-points-value=hover_points.to_json)
//     svg(data-balance-chart-target="svg" data-action="pointermove->balance-chart#track pointerleave->balance-chart#hide")
//       g(data-balance-chart-target="cursor") …
//
// Les libellés viennent de la base : ils passent par `textContent`, jamais
// par `innerHTML`.
const GAP = 12    // entre le point et la bulle
const MARGIN = 4  // marge minimale au bord de la fenêtre

export default class extends Controller {
  static targets = ["svg", "cursor", "guide", "dot"]
  static values = { points: Array }

  connect() {
    this.bubble = null
    this.current = null
    this.onScroll = () => this.hide()
  }

  disconnect() {
    this.hide()
  }

  track(event) {
    const x = this.toSvgX(event.clientX)
    if (x === null || this.pointsValue.length === 0) return

    const point = this.pointsValue.reduce((best, candidate) =>
      Math.abs(candidate.x - x) < Math.abs(best.x - x) ? candidate : best
    )
    if (point !== this.current) {
      this.current = point
      this.moveCursor(point)
      this.render(point)
    }
    this.position(point)
  }

  hide() {
    this.current = null
    if (this.hasCursorTarget) this.cursorTarget.setAttribute("visibility", "hidden")
    if (this.bubble) {
      this.bubble.remove()
      window.removeEventListener("scroll", this.onScroll, { capture: true })
    }
  }

  // --- Coordonnées ----------------------------------------------------------

  toSvgX(clientX) {
    const matrix = this.svgTarget.getScreenCTM()
    if (!matrix) return null
    const point = this.svgTarget.createSVGPoint()
    point.x = clientX
    point.y = 0
    return point.matrixTransform(matrix.inverse()).x
  }

  toScreen(point) {
    const matrix = this.svgTarget.getScreenCTM()
    const svgPoint = this.svgTarget.createSVGPoint()
    svgPoint.x = point.x
    svgPoint.y = point.y
    return svgPoint.matrixTransform(matrix)
  }

  moveCursor(point) {
    if (!this.hasCursorTarget) return
    this.guideTarget.setAttribute("x1", point.x)
    this.guideTarget.setAttribute("x2", point.x)
    this.dotTarget.setAttribute("cx", point.x)
    this.dotTarget.setAttribute("cy", point.y)
    this.cursorTarget.setAttribute("visibility", "visible")
  }

  // --- Bulle ----------------------------------------------------------------

  render(point) {
    if (!this.bubble) this.bubble = this.buildBubble()
    const body = this.bubble.firstChild
    body.replaceChildren()

    const head = document.createElement("div")
    head.className = "text-gray-300"
    head.textContent = point.projected ? `${point.date} · projeté` : point.date
    body.append(head)

    const balance = document.createElement("div")
    balance.className = `text-sm font-semibold tabular-nums ${point.negative ? "text-red-300" : "text-white"}`
    balance.textContent = `Solde : ${point.balance}`
    body.append(balance)

    if (point.movements.length > 0) {
      const list = document.createElement("ul")
      list.className = "mt-1 space-y-0.5 border-t border-gray-700 pt-1"
      point.movements.forEach((movement) => {
        const item = document.createElement("li")
        item.className = "flex gap-3"
        const label = document.createElement("span")
        label.className = "min-w-0 flex-1 truncate"
        label.textContent = movement.label
        const amount = document.createElement("span")
        amount.className = `shrink-0 tabular-nums ${movement.incoming ? "text-emerald-300" : "text-amber-200"}`
        amount.textContent = movement.amount
        item.append(label, amount)
        list.append(item)
      })
      if (point.more > 0) {
        const more = document.createElement("li")
        more.className = "text-gray-400"
        more.textContent = `et ${point.more} autre${point.more > 1 ? "s" : ""}`
        list.append(more)
      }
      body.append(list)
    } else if (point.projected) {
      const none = document.createElement("div")
      none.className = "text-gray-400"
      none.textContent = "Aucun mouvement attendu ce jour-là."
      body.append(none)
    }

    if (!this.bubble.isConnected) {
      document.body.appendChild(this.bubble)
      window.addEventListener("scroll", this.onScroll, { capture: true, passive: true })
    }
  }

  buildBubble() {
    const bubble = document.createElement("div")
    bubble.setAttribute("aria-hidden", "true")
    bubble.className = "pointer-events-none fixed left-0 top-0 z-50 w-max max-w-sm rounded-md bg-gray-900 px-3 py-2 text-xs font-medium leading-snug text-white shadow-lg"
    bubble.append(document.createElement("div"))
    return bubble
  }

  // Au-dessus du point s'il y a la place, en dessous sinon ; à droite de la
  // souris, ou à gauche près du bord droit.
  position(point) {
    const bubble = this.bubble
    const screen = this.toScreen(point)
    const width = bubble.offsetWidth
    const height = bubble.offsetHeight
    const viewportWidth = document.documentElement.clientWidth
    const viewportHeight = document.documentElement.clientHeight

    let left = screen.x + GAP
    if (left + width > viewportWidth - MARGIN) left = screen.x - GAP - width
    left = Math.max(left, MARGIN)

    let top = screen.y - GAP - height
    if (top < MARGIN) top = Math.min(screen.y + GAP, viewportHeight - height - MARGIN)

    bubble.style.left = `${Math.round(left)}px`
    bubble.style.top = `${Math.round(top)}px`
  }
}
