import { Controller } from "@hotwired/stimulus"

// Plusieurs photos avant un seul enregistrement (fiches de la carte, plantes).
// Sur iPhone, « Prendre une photo » n'en rend qu'une, et chaque nouveau choix
// remplace le précédent dans le champ : il fallait enregistrer entre deux
// photos. Ici, chaque photo prise ou choisie dans la photothèque s'ajoute à la
// liste (aperçu, croix pour la retirer) et toutes partent au même
// enregistrement.
//
// Deux champs fichier : `picker`, sans `name`, celui qu'ouvre le bouton ; et
// `field`, le vrai champ du formulaire (name, direct upload, required…), rempli
// à chaque ajout par un DataTransfer. Active Storage et `submit-progress` le
// lisent comme un champ rempli à la main : la progression d'envoi est inchangée.
//
// Usage : le partiel `shared/_photo_picker`, avec le vrai champ en bloc.
export default class extends Controller {
  static targets = ["picker", "field", "button", "buttonLabel", "previews", "template", "summary", "submit"]
  static values = {
    addLabel: { type: String, default: "Ajouter une photo" },
    addMoreLabel: { type: String, default: "Ajouter une autre photo" },
    saveLabel: { type: String, default: "Enregistrer" }
  }

  connect() {
    this.files = []
    this.urls = new Map()
    // Navigateur trop ancien pour remplir un champ fichier (Safari < 14.1) : on
    // rend le champ d'origine, une sélection à la fois comme avant.
    if (!canAssignFiles()) {
      this.fieldTarget.classList.remove("sr-only")
      this.fieldTarget.removeAttribute("tabindex")
      this.buttonTarget.hidden = true
    }
  }

  disconnect() {
    this.urls.forEach((url) => URL.revokeObjectURL(url))
    this.urls.clear()
  }

  add() {
    Array.from(this.pickerTarget.files || []).forEach((file) => {
      if (!this.files.some((other) => sameFile(other, file))) this.files.push(file)
    })
    // Vidé pour que la photo suivante déclenche bien un `change`.
    this.pickerTarget.value = ""
    this.sync()
  }

  remove(event) {
    const [file] = this.files.splice(Number(event.currentTarget.dataset.index), 1)
    if (file && this.urls.has(file)) {
      URL.revokeObjectURL(this.urls.get(file))
      this.urls.delete(file)
    }
    this.sync()
  }

  sync() {
    const transfer = new DataTransfer()
    this.files.forEach((file) => transfer.items.add(file))
    this.fieldTarget.files = transfer.files
    this.render()
  }

  render() {
    this.previewsTarget.replaceChildren(...this.files.map((file, index) => this.preview(file, index)))

    const count = this.files.length
    this.buttonLabelTarget.textContent = count ? this.addMoreLabelValue : this.addLabelValue
    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = count === 1
        ? `1 photo prête : elle part avec « ${this.saveLabelValue} ».`
        : `${count} photos prêtes : elles partent avec « ${this.saveLabelValue} ».`
      this.summaryTarget.classList.toggle("hidden", count === 0)
    }
    if (this.hasSubmitTarget) {
      this.submitTarget.textContent = count === 1 ? "Enregistrer la photo" : `Enregistrer les ${count} photos`
      this.submitTarget.classList.toggle("hidden", count === 0)
    }
  }

  preview(file, index) {
    const item = this.templateTarget.content.firstElementChild.cloneNode(true)
    const image = item.querySelector("img")
    if (!this.urls.has(file)) this.urls.set(file, URL.createObjectURL(file))
    image.src = this.urls.get(file)
    image.alt = file.name
    item.querySelector("button").dataset.index = index
    return item
  }
}

function canAssignFiles() {
  try {
    return typeof DataTransfer === "function" && new DataTransfer().files instanceof FileList
  } catch {
    return false
  }
}

function sameFile(a, b) {
  return a.name === b.name && a.size === b.size && a.lastModified === b.lastModified
}
