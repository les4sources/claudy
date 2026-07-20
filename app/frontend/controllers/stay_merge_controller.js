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
const STORAGE_STAMP = "claudy.stayMerge.stamp"
const SELECTION_TTL_MS = 60 * 60 * 1000 // sélection périmée au-delà d'une heure

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
    if (this.hasBannerTarget) {
      // Le bandeau est un conteneur flex : `hidden` et `flex` se toggleent
      // ensemble, sinon il s'affiche en block et écrase sa mise en page.
      this.bannerTarget.classList.toggle("hidden", !on)
      this.bannerTarget.classList.toggle("flex", on)
    }
    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.setAttribute("aria-pressed", on ? "true" : "false")
      // Swap COMPLET des classes d'état : ajouter bg-indigo-600 sans retirer
      // bg-white laisse gagner bg-white (ordre CSS Tailwind) → texte blanc sur
      // fond blanc. Chaque classe de base a son pendant actif.
      const activeClasses = ["bg-indigo-600", "text-white", "border-indigo-600", "hover:bg-indigo-700"]
      const baseClasses = ["bg-white", "text-gray-700", "border-gray-300", "hover:bg-gray-50"]
      activeClasses.forEach((c) => this.toggleButtonTarget.classList.toggle(c, on))
      baseClasses.forEach((c) => this.toggleButtonTarget.classList.toggle(c, !on))
    }
    // Les blocs notes du jour ajoutent du bruit en mode fusion (on désigne des
    // séjours, pas des notes). Le masquage est accroché ICI — la routine d'état
    // visuel du mode — et non dans le handler du clic : ainsi il suit AUSSI la
    // restauration au connect() (navigation de mois, sélection persistée en
    // sessionStorage) et la sortie du mode, sans duplication.
    this.toggleCalendarNotes(on)
  }

  // Masque (on=true) ou réaffiche (on=false) les blocs notes du calendrier. Ils
  // vivent hors du fragment de sélection, dans les cellules jour du template ERB
  // (data-calendar-notes). Un simple `hidden` suffit — au rechargement d'un mois,
  // l'état est reposé par applyModeChrome selon le mode restauré.
  toggleCalendarNotes(hidden) {
    document.querySelectorAll("[data-calendar-notes]").forEach((el) => {
      el.classList.toggle("hidden", hidden)
      if (hidden) {
        el.setAttribute("aria-hidden", "true")
      } else {
        el.removeAttribute("aria-hidden")
      }
    })
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

    this.element.querySelectorAll("[data-stay-id]").forEach((block) => {
      const id = String(block.dataset.stayId)
      const selected = ids.has(id)
      block.classList.toggle("merge-selected", selected)
      if (selected) {
        const hue = this.hueFor(id)
        block.style.boxShadow = `0 0 0 2px hsl(${hue} 65% 45%), 0 0 0 5px hsl(${hue} 70% 90%)`
        // Badge ✓ sur CHAQUE bloc du séjour : chaque fragment confirme sa
        // sélection, le ring seul est trop discret sur les petits blocs.
        this.addBadge(block, hue)
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
      // Libellé explicite VISIBLE quand la sélection est insuffisante (un title
      // seul est invisible au tactile), accord correct sinon.
      this.mergeButtonTarget.textContent =
        count < 2 ? "Sélectionne au moins 2 séjours" : `Fusionner ${count} séjours`
      this.mergeButtonTarget.title =
        count < 2 ? "Sélectionne au moins 2 séjours" : "Fusionner les séjours sélectionnés"
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
    // Désarme le bouton : le serveur est protégé contre le double POST, mais
    // inutile d'envoyer une requête vouée au 422.
    const submitButton = form.querySelector("button, input[type=submit]")
    if (submitButton) {
      if (submitButton.disabled) return
      submitButton.disabled = true
    }
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
      if (!Array.isArray(parsed)) return []
      // Sélection périmée (> 60 min) : on repart à neuf plutôt que de ré-entrer
      // en mode fusion avec des séjours choisis il y a longtemps.
      const stampRaw = sessionStorage.getItem(STORAGE_STAMP)
      const stamp = stampRaw ? parseInt(stampRaw, 10) : 0
      if (!stamp || Date.now() - stamp > SELECTION_TTL_MS) {
        this.clearStorage()
        return []
      }
      return parsed
    } catch (_e) {
      return []
    }
  }

  persistSelection() {
    sessionStorage.setItem(STORAGE_SELECTION, JSON.stringify(this.selection))
    sessionStorage.setItem(STORAGE_STAMP, String(Date.now()))
  }

  clearStorage() {
    sessionStorage.removeItem(STORAGE_ACTIVE)
    sessionStorage.removeItem(STORAGE_SELECTION)
    sessionStorage.removeItem(STORAGE_STAMP)
  }
}
