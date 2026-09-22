import { Controller } from "@hotwired/stimulus"

// Un <select> long qu'on peut CHERCHER (Michael, 2026-09-20).
//
// Le plan comptable fait plusieurs centaines de lignes et la liste des
// événements grandit à chaque saison : dérouler un <select> natif pour y
// trouver « 700100 Ventes bar » revient à lire l'annuaire. Ce contrôleur pose
// un champ de recherche par-dessus, filtre à la frappe, et se pilote au
// clavier.
//
// LE <select> RESTE LA SOURCE DE VÉRITÉ. Il est masqué quand JS est actif,
// jamais retiré : c'est lui que le formulaire soumet, et sans JS il reste
// utilisable tel quel — même dégradation gracieuse que `customer-search`.
//
// La recherche ignore les accents ET la casse : « evenement » trouve
// « Événement », « epicerie » trouve « Épicerie ». Sans ça, il faut taper
// juste pour trouver, ce qui est exactement ce qu'on essaie d'éviter.
//
// Usage (dans une vue) :
//   div(data-controller="searchable-select" class="relative")
//     = f.collection_select …, data: { searchable_select_target: "select" }
//     div(data-searchable-select-target="wrap" class="hidden")
//       input(data-searchable-select-target="input"
//             data-action="input->searchable-select#filter focus->searchable-select#open keydown->searchable-select#navigate")
//       ul(data-searchable-select-target="list" class="hidden")
export default class extends Controller {
  static targets = ["select", "wrap", "input", "list"]
  static values = { placeholder: { type: String, default: "Chercher…" }, max: { type: Number, default: 50 } }

  connect() {
    this.options = Array.from(this.selectTarget.options).map((option, index) => ({
      index,
      value: option.value,
      label: option.text.trim(),
      cle: this.constructor.normaliser(option.text)
    }))

    this.selectTarget.classList.add("hidden")
    this.wrapTarget.classList.remove("hidden")
    this.inputTarget.placeholder = this.placeholderValue
    this.actif = -1
    this.refleterLaSelection()

    this.fermerAuClicDehors = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    document.addEventListener("click", this.fermerAuClicDehors)
  }

  disconnect() {
    document.removeEventListener("click", this.fermerAuClicDehors)
  }

  // Le libellé de l'option retenue, ou rien si c'est l'option vide : le
  // placeholder dit alors ce qu'on attend, ce qu'un « Choisir… » écrit en dur
  // dans le champ ne ferait pas — on le prendrait pour une valeur.
  refleterLaSelection() {
    const choisie = this.options.find((o) => o.value === this.selectTarget.value)
    this.inputTarget.value = choisie && choisie.value !== "" ? choisie.label : ""
  }

  open() {
    this.filter()
  }

  close() {
    this.listTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.actif = -1
    // Le champ ne garde jamais un texte qui ne correspond à rien : sinon on
    // croit avoir choisi « Ventes bar » alors que le <select> est resté vide.
    this.refleterLaSelection()
  }

  filter() {
    const requete = this.constructor.normaliser(this.inputTarget.value)
    const visibles = this.options
      .filter((o) => o.value !== "" && (requete === "" || o.cle.includes(requete)))
      .slice(0, this.maxValue)

    this.visibles = visibles
    this.actif = visibles.length ? 0 : -1
    this.dessiner()
  }

  dessiner() {
    if (!this.visibles.length) {
      this.listTarget.innerHTML =
        '<li class="px-3 py-2 text-sm text-gray-500">Aucun résultat</li>'
    } else {
      this.listTarget.innerHTML = this.visibles
        .map(
          (o, rang) =>
            `<li role="option" id="${this.identifiant(rang)}" data-index="${o.index}" data-action="mousedown->searchable-select#choisirDepuisLaListe" aria-selected="${rang === this.actif}" class="cursor-pointer px-3 py-2 text-sm ${rang === this.actif ? "bg-gray-100 text-gray-900" : "text-gray-700"}">${this.constructor.echapper(o.label)}</li>`
        )
        .join("")
    }
    this.listTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.marquerActif()
  }

  navigate(event) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (this.listTarget.classList.contains("hidden")) return this.filter()
      const pas = event.key === "ArrowDown" ? 1 : -1
      this.actif = Math.min(Math.max(this.actif + pas, 0), this.visibles.length - 1)
      this.marquerActif()
    } else if (event.key === "Enter") {
      if (this.listTarget.classList.contains("hidden")) return
      event.preventDefault()
      if (this.actif >= 0) this.choisir(this.visibles[this.actif].index)
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  choisirDepuisLaListe(event) {
    // `mousedown` et pas `click` : le `blur` du champ part avant le clic et
    // refermerait la liste sous le curseur.
    event.preventDefault()
    this.choisir(Number(event.currentTarget.dataset.index))
  }

  choisir(index) {
    this.selectTarget.selectedIndex = index
    // Les écrans qui écoutent le <select> (un `auto-submit`, un calcul de
    // total) doivent voir passer le changement comme si un humain l'avait fait.
    this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
  }

  marquerActif() {
    Array.from(this.listTarget.children).forEach((li, rang) => {
      const actif = rang === this.actif
      li.setAttribute("aria-selected", actif ? "true" : "false")
      li.classList.toggle("bg-gray-100", actif)
      li.classList.toggle("text-gray-900", actif)
      li.classList.toggle("text-gray-700", !actif)
      if (actif) li.scrollIntoView({ block: "nearest" })
    })
    const courant = this.actif >= 0 ? this.identifiant(this.actif) : ""
    this.inputTarget.setAttribute("aria-activedescendant", courant)
  }

  identifiant(rang) {
    return `${this.element.id || this.selectTarget.name.replace(/\W+/g, "-")}-option-${rang}`
  }

  static normaliser(texte) {
    return texte
      .toString()
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .trim()
  }

  static echapper(texte) {
    const div = document.createElement("div")
    div.textContent = texte
    return div.innerHTML
  }
}
