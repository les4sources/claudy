import { Controller } from "@hotwired/stimulus"

// Galerie photo d'un gîte, ouverte depuis les cartes de l'étape 2.
//
// Le contenu arrive par Turbo Frame : ouvrir pose le `src` du frame et le
// serveur rend la galerie. Aucune image n'est construite en JavaScript, et le
// texte alternatif reste écrit en Ruby, là où on peut le relire. Surtout, les
// 39 photos ne partent PAS dans chaque rendu de la page de composition — elles
// n'existent que pour qui ouvre une galerie.
//
// Mêmes obligations que tout dialogue modal : Escape ferme, le focus entre et
// ne sort pas, il revient sur la carte qui a ouvert.
const FOCUSABLE = [
  "a[href]",
  "button:not([disabled])",
  '[tabindex]:not([tabindex="-1"])'
].join(",")

export default class extends Controller {
  static targets = ["overlay", "modal", "title", "counter", "body", "loading"]

  connect() {
    this.onKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.body.classList.remove("overflow-hidden")
  }

  open(event) {
    const trigger = event.currentTarget
    const name = trigger.dataset.galleryLodging
    const url = trigger.dataset.galleryUrl
    if (!name || !url) return

    this.previouslyFocused = trigger

    if (this.hasTitleTarget) this.titleTarget.textContent = name
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = trigger.dataset.galleryCount || ""
    }

    this.overlayTarget.classList.remove("hidden")
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    if (this.hasBodyTarget) this.bodyTarget.scrollTop = 0
    this.modalTarget.focus()

    this.loadGallery(url)
  }

  // Fetch manuel plutôt que `frame.src = url`. Ce n'est pas un choix de style :
  // Turbo Frame ne met pas à jour un frame qui vit dans une modale `fixed`
  // masquée — le repo le documente déjà dans `avail_modal_controller`, qui
  // charge son calendrier de la même façon. Poser `src` déclenche bien la
  // requête (200 dans le réseau) mais le contenu n'est jamais échangé.
  //
  // Ne recharge pas une galerie déjà affichée : passer d'un gîte à l'autre puis
  // revenir au premier est instantané.
  async loadGallery(url) {
    const frame = this.element.querySelector("#lodging_gallery")
    if (!frame || frame.dataset.loadedFrom === url) return

    try {
      const res = await fetch(url, { headers: { Accept: "text/html" } })
      const html = await res.text()
      const doc = new DOMParser().parseFromString(html, "text/html")
      const fresh = doc.getElementById("lodging_gallery")
      if (!fresh) return
      frame.innerHTML = fresh.innerHTML
      frame.dataset.loadedFrom = url
    } catch (_e) {
      // Échec réseau : on laisse le message de chargement, l'utilisateur peut
      // refermer et rouvrir. Rien de destructif.
    }
  }

  close() {
    if (!this.isOpen) return
    this.overlayTarget.classList.add("hidden")
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")

    if (this.previouslyFocused && document.contains(this.previouslyFocused)) {
      this.previouslyFocused.focus()
    }
    this.previouslyFocused = null
  }

  get isOpen() {
    return this.hasModalTarget && !this.modalTarget.classList.contains("hidden")
  }

  handleKeydown(event) {
    if (!this.isOpen) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }
    if (event.key === "Tab") this.trapFocus(event)
  }

  trapFocus(event) {
    const focusables = Array.from(this.modalTarget.querySelectorAll(FOCUSABLE)).filter(
      (el) => el.offsetParent !== null
    )
    if (focusables.length === 0) {
      event.preventDefault()
      this.modalTarget.focus()
      return
    }
    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    const active = document.activeElement

    if (event.shiftKey && (active === first || active === this.modalTarget)) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && active === last) {
      event.preventDefault()
      first.focus()
    }
  }
}
