import { Controller } from "@hotwired/stimulus"

// Barre latérale de la nouvelle interface (Michael 2026-10-24) : repliée en
// icônes seules pour qui a besoin de largeur, avec une infobulle au survol ou
// au focus de chaque entrée.
//
// Le choix vit dans un cookie (`ui_side`) : le serveur pose la classe
// `ui-side-collapsed` sur <body> dès le rendu, la page n'arrive jamais dépliée
// puis repliée.
//
// L'infobulle est en `position: fixed`, posée ici à hauteur de l'entrée :
// la barre défile (`overflow-y: auto`) et couperait une bulle en CSS pur.
const COOKIE = "ui_side"

export default class extends Controller {
  static targets = ["tip", "toggle"]

  toggle() {
    const collapsed = document.body.classList.toggle("ui-side-collapsed")
    const maxAge = collapsed ? 60 * 60 * 24 * 365 : 0
    document.cookie = `${COOKIE}=collapsed; path=/; max-age=${maxAge}; samesite=lax`
    this.toggleTarget.setAttribute("aria-expanded", collapsed ? "false" : "true")
    this.toggleTarget.dataset.tip = collapsed ? "Déplier la barre" : "Replier la barre"
    this.hideTip()
    if (collapsed) this.showTipFor(this.toggleTarget)
  }

  showTip(event) {
    const item = event.target.closest("[data-tip]")
    if (!item || !this.element.contains(item)) return
    this.showTipFor(item)
  }

  showTipFor(item) {
    if (!document.body.classList.contains("ui-side-collapsed")) return
    const rect = item.getBoundingClientRect()
    this.tipTarget.textContent = item.dataset.tip
    this.tipTarget.hidden = false
    this.tipTarget.style.top = `${rect.top + rect.height / 2}px`
    this.tipTarget.style.left = `${rect.right + 12}px`
  }

  hideTip(event) {
    // Passer d'une entrée à son icône ne doit pas faire clignoter la bulle.
    if (event?.relatedTarget && event.target.closest("[data-tip]")?.contains(event.relatedTarget)) return
    this.tipTarget.hidden = true
  }
}
