import { Controller } from "@hotwired/stimulus"

// Le formulaire d'une facture d'achat (epic #240, phase 2).
//
// Deux choses que le serveur ne peut pas faire à temps : montrer ce qu'il RESTE
// à ventiler pendant qu'on tape, et accepter le PDF qu'on fait glisser depuis sa
// boîte mail. Sans le reste-à-ventiler affiché, on découvre le déséquilibre à la
// validation, une fois les vingt lignes tapées.
export default class extends Controller {
  static targets = ["rows", "template", "row", "total", "allocated", "vat", "remaining", "verdict",
                    "dropzone", "file", "filename", "previewFrame", "previewImage", "previewEmpty"]

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

  // Les lignes se tapent HTVA avec leur taux, comme sur la pièce. La TVA se
  // calcule taux par taux sur la somme des bases, comme le fournisseur l'a
  // calculée (et comme `PurchaseInvoice#compute_vat` l'enregistre) : le reste à
  // ventiler compare alors le total TVAC à des lignes TVA comprise.
  refresh() {
    const totalCents = this.toCents(this.totalTarget.value)
    const basesByRate = new Map()

    this.rowTargets.forEach((row) => {
      if (row.hidden) return
      const net = this.toCents(row.querySelector("[data-role='amount']")?.value)
      const rate = parseInt(row.querySelector("[data-role='vat-rate']")?.value ?? "0", 10) || 0
      basesByRate.set(rate, (basesByRate.get(rate) ?? 0) + net)
    })

    let netCents = 0
    let vatCents = 0
    basesByRate.forEach((base, rate) => {
      netCents += base
      vatCents += Math.sign(base) * Math.round(Math.abs(base) * rate / 100)
    })

    const remaining = totalCents - netCents - vatCents

    this.allocatedTarget.textContent = this.format(netCents)
    if (this.hasVatTarget) this.vatTarget.textContent = this.format(vatCents)
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
    if (file) this.preview(file)
  }

  // La pièce s'affiche à côté des champs : on relit la saisie contre le
  // document, pas de mémoire. Une pièce déposée à la main s'affiche tout de
  // suite, avant tout envoi, depuis le fichier local.
  preview(file) {
    if (!this.hasPreviewFrameTarget) return

    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = URL.createObjectURL(file)
    const image = file.type.startsWith("image/")

    this.previewFrameTarget.hidden = image
    this.previewImageTarget.hidden = !image
    if (image) {
      this.previewImageTarget.src = this.objectUrl
    } else {
      this.previewFrameTarget.src = `${this.objectUrl}#navpanes=0&view=FitH`
    }
    if (this.hasPreviewEmptyTarget) this.previewEmptyTarget.hidden = true
  }

  disconnect() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
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
