import { Controller } from "@hotwired/stimulus"

// Mode fusion de séjours depuis le calendrier admin (epic #81, Phase 2).
//
// Parti pris : la teinte unique de chaque séjour (stay_hue, angle d'or — même
// formule que CalendarHelper) porte toute l'identité visuelle. On clique un bloc,
// c'est TOUT le séjour qui s'allume de sa couleur à travers la grille.
//
// Le mode et la sélection survivent à la navigation entre mois (rechargements
// simple_calendar) via sessionStorage. Les étapes A (désignation) et B (aperçu)
// du dialog sont des fragments SERVEUR (fetch) : aucune vérité recalculée en JS.
//
// Placé sur le wrapper du calendrier, à côté de stay-details. En mode actif, un
// handler en phase CAPTURE neutralise l'ouverture de la modale séjour pour
// transformer le clic en sélection. Mode inactif = zéro interférence.
const GOLDEN_ANGLE = 137.508
const STORAGE_ACTIVE = "claudy.stayMerge.active"
const STORAGE_SELECTION = "claudy.stayMerge.selection"

export default class extends Controller {
  static targets = ["bar", "chips", "count", "mergeButton", "dialog", "dialogContent", "toggleButton", "banner"]
  static values = { setupUrl: String, previewUrl: String, reset: Boolean }

  connect() {
    // Fusion tout juste réalisée (redirection ?stay_merge_done=1) : on repart propre.
    if (this.resetValue) {
      this.clearStorage()
    }

    this.active = sessionStorage.getItem(STORAGE_ACTIVE) === "1"
    this.selection = this.readSelection()
    this.lastTargetId = null

    this.boundClick = this.handleClick.bind(this)
    this.boundKeydown = this.handleKeydown.bind(this)
    // Capture pour passer AVANT l'action bubble stay-details#open des overlays.
    this.element.addEventListener("click", this.boundClick, true)
    window.addEventListener("keydown", this.boundKeydown)

    if (this.active) {
      this.applyModeChrome(true)
    }
    this.applySelectionStyles()
    this.renderBar()
  }

  disconnect() {
    this.element.removeEventListener("click", this.boundClick, true)
    window.removeEventListener("keydown", this.boundKeydown)
  }

  // --- Bascule du mode -------------------------------------------------------
  toggle() {
    this.active ? this.exitMode() : this.enterMode()
  }

  enterMode() {
    this.active = true
    sessionStorage.setItem(STORAGE_ACTIVE, "1")
    this.applyModeChrome(true)
    this.applySelectionStyles()
    this.renderBar()
  }

  exitMode() {
    this.active = false
    this.selection = []
    this.clearStorage()
    this.applyModeChrome(false)
    this.applySelectionStyles()
    this.renderBar()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  applyModeChrome(on) {
    this.element.classList.toggle("merge-mode", on)
    if (this.hasBannerTarget) this.bannerTarget.classList.toggle("hidden", !on)
    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.setAttribute("aria-pressed", on ? "true" : "false")
      this.toggleButtonTarget.classList.toggle("bg-indigo-600", on)
      this.toggleButtonTarget.classList.toggle("text-white", on)
      this.toggleButtonTarget.classList.toggle("border-indigo-600", on)
    }
  }

  // --- Sélection d'un séjour entier -----------------------------------------
  handleClick(event) {
    if (!this.active) return
    const block = event.target.closest("[data-stay-id]")
    if (!block) return
    const id = block.dataset.stayId
    if (!id) return

    // Neutralise l'ouverture de la modale / la navigation du lien du bloc.
    event.preventDefault()
    event.stopPropagation()
    this.toggleStay(block)
  }

  toggleStay(block) {
    const id = String(block.dataset.stayId)
    const existing = this.selection.findIndex((s) => String(s.id) === id)
    if (existing >= 0) {
      this.selection.splice(existing, 1)
    } else {
      this.selection.push({
        id,
        label: block.dataset.stayLabel || `Séjour #${id}`,
        dates: block.dataset.stayDates || ""
      })
    }
    this.persistSelection()
    this.applySelectionStyles()
    this.renderBar()
  }

  clearSelection() {
    this.selection = []
    this.persistSelection()
    this.applySelectionStyles()
    this.renderBar()
  }

  removeChip(event) {
    const id = String(event.currentTarget.dataset.stayId)
    this.selection = this.selection.filter((s) => String(s.id) !== id)
    this.persistSelection()
    this.applySelectionStyles()
    this.renderBar()
  }

  // --- Rendu de la sélection (teinte séjour, estompage, badge ✓) -------------
  applySelectionStyles() {
    const ids = new Set(this.selection.map((s) => String(s.id)))
    this.element.classList.toggle("has-selection", this.selection.length > 0)

    const seen = new Set()
    this.element.querySelectorAll("[data-stay-id]").forEach((block) => {
      const id = String(block.dataset.stayId)
      const selected = ids.has(id)
      block.classList.toggle("merge-selected", selected)
      if (selected) {
        const hue = this.hueFor(id)
        block.style.boxShadow = `0 0 0 2px hsl(${hue} 65% 45%), 0 0 0 5px hsl(${hue} 70% 90%)`
        if (!seen.has(id)) {
          seen.add(id)
          this.addBadge(block, hue)
        } else {
          this.removeBadge(block)
        }
      } else {
        block.style.boxShadow = ""
        this.removeBadge(block)
      }
    })
  }

  addBadge(block, hue) {
    if (block.querySelector(":scope > .merge-selection-badge")) return
    const badge = document.createElement("span")
    badge.className = "merge-selection-badge"
    badge.style.backgroundColor = `hsl(${hue} 65% 45%)`
    badge.textContent = "✓"
    badge.setAttribute("aria-hidden", "true")
    block.appendChild(badge)
  }

  removeBadge(block) {
    const badge = block.querySelector(":scope > .merge-selection-badge")
    if (badge) badge.remove()
  }

  // --- Bottom bar : chips + compteur + bouton --------------------------------
  renderBar() {
    if (!this.hasBarTarget) return
    const count = this.selection.length

    if (count === 0) {
      this.barTarget.classList.add("translate-y-full")
      this.barTarget.hidden = true
      if (this.hasChipsTarget) this.chipsTarget.innerHTML = ""
      return
    }

    this.barTarget.hidden = false
    // rAF pour laisser le hidden=false s'appliquer avant la transition d'entrée.
    requestAnimationFrame(() => this.barTarget.classList.remove("translate-y-full"))

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${count} séjour${count > 1 ? "s" : ""} sélectionné${count > 1 ? "s" : ""}`
    }
    if (this.hasMergeButtonTarget) {
      this.mergeButtonTarget.disabled = count < 2
      this.mergeButtonTarget.title = count < 2 ? "Sélectionne au moins 2 séjours" : "Fusionner les séjours sélectionnés"
      this.mergeButtonTarget.textContent = `Fusionner ${count} séjours`
    }
    if (this.hasChipsTarget) this.renderChips()
  }

  renderChips() {
    this.chipsTarget.innerHTML = ""
    this.selection.forEach((stay) => {
      const hue = this.hueFor(stay.id)
      const chip = document.createElement("span")
      chip.className = "inline-flex items-center gap-1.5 flex-shrink-0 rounded-full border border-gray-200 bg-white pl-2 pr-1 py-1 text-xs text-gray-700"

      const dot = document.createElement("span")
      dot.className = "inline-block h-2.5 w-2.5 rounded-full flex-shrink-0"
      dot.style.backgroundColor = `hsl(${hue} 65% 45%)`
      chip.appendChild(dot)

      const label = document.createElement("span")
      label.className = "whitespace-nowrap"
      const parts = [`#${stay.id}`, stay.label, stay.dates].filter((p) => p && p.length)
      label.textContent = parts.join(" · ")
      chip.appendChild(label)

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "ml-0.5 text-gray-400 hover:text-gray-600 px-1"
      remove.textContent = "×"
      remove.setAttribute("aria-label", `Retirer le séjour #${stay.id}`)
      remove.dataset.stayId = stay.id
      remove.dataset.action = "stay-merge#removeChip"
      chip.appendChild(remove)

      this.chipsTarget.appendChild(chip)
    })
  }

  // --- Dialog 2 étapes (fragments serveur) -----------------------------------
  async openDialog() {
    if (this.selection.length < 2) return
    this.setDialogLoading()
    this.dialogTarget.showModal()
    await this.loadSetup()
  }

  async loadSetup(targetId = null) {
    const params = {}
    if (targetId) params.target_id = targetId
    await this.injectFragment(this.setupUrlValue, params)
  }

  async showPreview() {
    const checked = this.dialogContentTarget.querySelector('input[name="target_id"]:checked')
    this.lastTargetId = checked ? checked.value : null
    this.setDialogLoading()
    await this.injectFragment(this.previewUrlValue, this.lastTargetId ? { target_id: this.lastTargetId } : {})
  }

  async backToSetup() {
    this.setDialogLoading()
    await this.loadSetup(this.lastTargetId)
  }

  // Commit : le button_to (form réel) est intercepté ici pour rester DANS le
  // dialog en cas d'erreur (422) et suivre la redirection en cas de succès.
  async commit(event) {
    event.preventDefault()
    const form = event.currentTarget
    try {
      const response = await fetch(form.action, {
        method: "POST",
        headers: { Accept: "application/json" },
        body: new FormData(form)
      })
      const contentType = response.headers.get("content-type") || ""
      if (response.ok && contentType.includes("json")) {
        const data = await response.json()
        window.location.href = data.redirect
      } else {
        // Garde-fou serveur : on ré-injecte le fragment d'aperçu avec l'erreur.
        this.dialogContentTarget.innerHTML = await response.text()
      }
    } catch (_e) {
      this.dialogContentTarget.innerHTML =
        '<div class="px-6 py-8 text-center text-sm text-red-600">Erreur réseau — réessaie.</div>'
    }
  }

  closeDialog(event) {
    if (event) event.preventDefault()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  // --- Helpers ---------------------------------------------------------------
  setDialogLoading() {
    this.dialogContentTarget.innerHTML =
      '<div class="px-6 py-8 text-center text-sm text-gray-500">Chargement…</div>'
  }

  async injectFragment(url, extraParams) {
    const body = new URLSearchParams()
    this.selection.forEach((s) => body.append("stay_ids[]", s.id))
    Object.entries(extraParams).forEach(([k, v]) => body.append(k, v))
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken(),
          Accept: "text/html"
        },
        body: body.toString()
      })
      this.dialogContentTarget.innerHTML = await response.text()
    } catch (_e) {
      this.dialogContentTarget.innerHTML =
        '<div class="px-6 py-8 text-center text-sm text-red-600">Erreur de chargement.</div>'
    }
  }

  hueFor(id) {
    return Math.round((Number(id) * GOLDEN_ANGLE) % 360)
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  handleKeydown(event) {
    if (event.key !== "Escape") return
    // Le dialog ouvert gère son propre Échap (fermeture native).
    if (this.hasDialogTarget && this.dialogTarget.open) return
    if (this.active) this.exitMode()
  }

  readSelection() {
    try {
      const raw = sessionStorage.getItem(STORAGE_SELECTION)
      const parsed = raw ? JSON.parse(raw) : []
      return Array.isArray(parsed) ? parsed : []
    } catch (_e) {
      return []
    }
  }

  persistSelection() {
    sessionStorage.setItem(STORAGE_SELECTION, JSON.stringify(this.selection))
  }

  clearStorage() {
    sessionStorage.removeItem(STORAGE_ACTIVE)
    sessionStorage.removeItem(STORAGE_SELECTION)
  }
}
