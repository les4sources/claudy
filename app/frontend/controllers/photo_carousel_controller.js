import { Controller } from "@hotwired/stimulus"

// Les photos d'un objet de la carte en carousel, en haut de sa fiche ; au
// toucher, la photo s'ouvre en plein écran et l'on continue d'y faire défiler
// les autres (flèches, clavier, glisser du doigt).
//
// Deux pistes à défilement aimanté (`scroll-snap`) : celle de la fiche et celle
// du plein écran. Le doigt fait défiler nativement ; les flèches et le clavier
// ne font que déplacer la piste d'une largeur. La position se lit au défilement,
// et passe d'une piste à l'autre à l'ouverture et à la fermeture.
//
// Le plein écran est un `<dialog>` ouvert par `showModal()` : il monte dans la
// couche supérieure du navigateur, au-dessus de la carte et hors du cadre de la
// fiche (dont `overflow` et `z-index` le couperaient). Escape le ferme d'office.
//
// Usage : le partiel `shared/_photo_carousel`.
export default class extends Controller {
  static targets = ["track", "counter", "dialog", "dialogTrack", "dialogCounter"]

  connect() {
    this.index = 0
    this.render()
  }

  disconnect() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  get count() {
    return this.trackTarget.children.length
  }

  // ── Carousel de la fiche ──────────────────────────────────────────────────
  previous() {
    this.scrollTo(this.trackTarget, this.index - 1)
  }

  next() {
    this.scrollTo(this.trackTarget, this.index + 1)
  }

  scrolled() {
    this.index = this.indexOf(this.trackTarget)
    this.render()
  }

  // ── Plein écran ───────────────────────────────────────────────────────────
  open(event) {
    const index = Number(event.currentTarget.dataset.index || 0)
    this.dialogTarget.showModal()
    this.jumpTo(this.dialogTrackTarget, index)
    this.index = index
    this.render()
  }

  close() {
    this.dialogTarget.close()
  }

  // Le dialogue se ferme aussi par Escape : la fiche reprend sur la photo vue.
  closed() {
    this.jumpTo(this.trackTarget, this.index)
    this.render()
  }

  dialogPrevious() {
    this.scrollTo(this.dialogTrackTarget, this.index - 1)
  }

  dialogNext() {
    this.scrollTo(this.dialogTrackTarget, this.index + 1)
  }

  dialogScrolled() {
    this.index = this.indexOf(this.dialogTrackTarget)
    this.render()
  }

  keydown(event) {
    if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.dialogPrevious()
    } else if (event.key === "ArrowRight") {
      event.preventDefault()
      this.dialogNext()
    }
  }

  // Un clic sur le fond noir, hors de la photo et des boutons, referme.
  backdrop(event) {
    if (event.target === event.currentTarget || event.target.dataset.photoCarouselBackdrop) this.close()
  }

  // ── Outils ────────────────────────────────────────────────────────────────
  indexOf(track) {
    const width = track.clientWidth
    if (!width) return this.index
    return Math.max(0, Math.min(this.count - 1, Math.round(track.scrollLeft / width)))
  }

  scrollTo(track, index) {
    const target = Math.max(0, Math.min(this.count - 1, index))
    track.scrollTo({ left: target * track.clientWidth, behavior: "smooth" })
  }

  jumpTo(track, index) {
    track.scrollTo({ left: index * track.clientWidth, behavior: "instant" })
  }

  render() {
    const label = `${this.index + 1} / ${this.count}`
    this.counterTargets.forEach((el) => { el.textContent = label })
    this.dialogCounterTargets.forEach((el) => { el.textContent = label })
    this.element.querySelectorAll("[data-photo-carousel-previous]").forEach((el) => { el.disabled = this.index === 0 })
    this.element.querySelectorAll("[data-photo-carousel-next]").forEach((el) => { el.disabled = this.index >= this.count - 1 })
  }
}
