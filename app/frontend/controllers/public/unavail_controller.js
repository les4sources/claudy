import { Controller } from "@hotwired/stimulus"

// Mini-modale « hébergement indisponible » (feature 1). Une cellule
// d'hébergement indisponible de la grille nuit par nuit ouvre, au clic, un
// <dialog> natif expliquant pourquoi, avec un lien vers le calendrier de
// disponibilités existant du funnel (public--avail-modal).
//
// Le lien « Voir les disponibilités » n'a de sens que là où cette modale
// existe (étape 2 du funnel). Dans le formulaire de modification client, où la
// modale n'est pas rendue, on masque le bouton — le message explicatif suffit.
export default class extends Controller {
  static targets = ["dialog", "message", "availLink", "alternatives"]

  // Les autres gîtes libres cette nuit-là, calculés côté serveur et posés sur la
  // cellule. La modale se contentait de constater le refus — un cul-de-sac : le
  // client lisait « pas libre » et n'avait aucune piste, alors que le gîte voisin
  // était peut-être disponible pour exactement les mêmes nuits.
  renderAlternatives(cell) {
    if (!this.hasAlternativesTarget) return

    let names = []
    try {
      names = JSON.parse(cell.getAttribute("data-unavail-alternatives") || "[]")
    } catch (_e) {
      names = []
    }

    if (names.length === 0) {
      this.alternativesTarget.classList.add("hidden")
      this.alternativesTarget.textContent = ""
      return
    }

    const liste =
      names.length === 1
        ? names[0]
        : `${names.slice(0, -1).join(", ")} et ${names[names.length - 1]}`
    this.alternativesTarget.textContent =
      names.length === 1
        ? `${liste} est libre cette nuit-là.`
        : `${liste} sont libres cette nuit-là.`
    this.alternativesTarget.classList.remove("hidden")
  }

  // Y a-t-il une modale de disponibilités dans la page ?
  get hasAvailModal() {
    return !!document.querySelector('[data-controller~="public--avail-modal"]')
  }

  show(event) {
    event.preventDefault()
    const cell = event.currentTarget
    const name = cell.getAttribute("data-unavail-name") || "Cet hébergement"
    const date = cell.getAttribute("data-unavail-date") || ""

    if (this.hasMessageTarget) {
      this.messageTarget.textContent = date
        ? `${name} n'est pas libre le ${date}.`
        : `${name} n'est pas libre pour cette nuit.`
    }

    this.renderAlternatives(cell)

    if (this.hasAvailLinkTarget) {
      this.availLinkTarget.classList.toggle("hidden", !this.hasAvailModal)
    }

    if (this.hasDialogTarget && typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  // Ferme la mini-modale puis demande l'ouverture du calendrier de
  // disponibilités via un évènement window écouté par public--avail-modal.
  openAvailability(event) {
    if (event) event.preventDefault()
    this.close()
    window.dispatchEvent(new CustomEvent("reservation:open-avail"))
  }
}
