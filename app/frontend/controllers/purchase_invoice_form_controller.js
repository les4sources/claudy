import { Controller } from "@hotwired/stimulus"

// Le formulaire d'une facture d'achat (epic #240, phase 2).
//
// Deux choses que le serveur ne peut pas faire à temps : montrer ce qu'il RESTE
// à ventiler pendant qu'on tape, et accepter le PDF qu'on fait glisser depuis sa
// boîte mail. Sans le reste-à-ventiler affiché, on découvre le déséquilibre à la
// validation, une fois les vingt lignes tapées.
export default class extends Controller {
  static targets = ["rows", "template", "row", "total", "allocated", "remaining", "verdict",
                    "dropzone", "file", "filename"]

  connect() {
    this.counter = 0
    this.refresh()
  }

  add(event) {
    event.preventDefault()

    const html = this.templateTarget.innerHTML.replaceAll("NEW_RECORD", this.nextIndex())
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.rowsTarget.lastElementChild?.querySelector("select, input")?.focus()
    this.refresh()
  }

  remove(event) {
    event.preventDefault()

    const row = event.target.closest("[data-purchase-invoice-form-target='row']")
    if (!row) return

    const destroy = row.querySelector("input[name*='_destroy']")
    if (destroy) {
      destroy.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }
    this.refresh()
  }

  refresh() {
    const totalCents = this.toCents(this.totalTarget.value)
    let allocatedCents = 0

    this.rowTargets.forEach((row) => {
      if (row.hidden) return
      allocatedCents += this.toCents(row.querySelector("[data-role='amount']")?.value)
    })

    const remaining = totalCents - allocatedCents

    this.allocatedTarget.textContent = this.format(allocatedCents)
    this.remainingTarget.textContent = this.format(remaining)

    if (this.hasVerdictTarget) {
      if (remaining === 0 && totalCents !== 0) {
        this.verdictTarget.textContent = "La ventilation couvre la facture."
        this.verdictTarget.className = "text-sm font-medium text-emerald-700"
      } else {
        this.verdictTarget.textContent = remaining > 0
          ? "Il reste à ventiler avant de pouvoir envoyer au paiement."
          : "La ventilation dépasse le total de la facture."
        this.verdictTarget.className = "text-sm font-medium text-orange-700"
      }
    }
  }

  // Glisser-déposer : la facture arrive par email, on la fait glisser depuis
  // l'onglet d'à côté. Le clic sur la zone reste possible.
  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("ring-2", "ring-4s-main")
  }

  dragleave() {
    this.dropzoneTarget.classList.remove("ring-2", "ring-4s-main")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("ring-2", "ring-4s-main")

    const file = event.dataTransfer?.files?.[0]
    if (!file) return

    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.fileTarget.files = transfer.files
    this.showFilename()
  }

  showFilename() {
    if (!this.hasFilenameTarget) return

    const file = this.fileTarget.files?.[0]
    this.filenameTarget.textContent = file ? file.name : "Aucune pièce choisie"
  }

  toCents(value) {
    const euros = parseFloat(String(value ?? "").replace(",", "."))
    return Number.isNaN(euros) ? 0 : Math.round(euros * 100)
  }

  format(cents) {
    return new Intl.NumberFormat("fr-BE", { style: "currency", currency: "EUR" }).format(cents / 100)
  }

  nextIndex() {
    this.counter += 1
    return `${Date.now()}${this.counter}`
  }
}
