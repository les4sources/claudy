import { Controller } from "@hotwired/stimulus"

// La section Documents (Michael, 2026-11-12) : ranger à la souris.
//
// - Glisser un fichier ou un dossier (ou toute la sélection cochée) sur un
//   dossier — sa tuile, l'arbre de gauche ou une étape du fil d'Ariane — l'y
//   déplace (`PATCH /documents/deplacer`).
// - Déposer des fichiers venus du bureau n'importe où sur la page les envoie
//   dans le dossier ouvert ; sur une tuile ou un dossier de l'arbre, dans ce
//   dossier-là. L'envoi montre sa progression, puis la page se recharge.
// - Les mêmes gestes sans glisser : menu ⋯, cases à cocher, fenêtres
//   « Nouveau dossier », « Renommer », « Déplacer vers… ».
//
// Chaque geste repart au serveur, qui vérifie l'accès et répond un message ;
// la page se recharge (Turbo) et le message s'affiche dans le bandeau. Un refus
// (un dossier dans lui-même, un nom déjà pris) s'affiche sans recharger.
const INTERNAL = "application/x-claudy-documents"

export default class extends Controller {
  static targets = [
    "item", "drop", "selectionBar", "selectionCount", "selectAll",
    "folderDialog", "renameDialog", "renameForm", "renameInput", "renameLabel", "renameHint",
    "moveDialog", "moveForm", "moveIds", "moveSelect", "moveOptions", "moveWhat",
    "uploadForm", "fileInput", "uploadPanel", "uploadTitle", "uploadBar", "uploadDetail",
    "veil", "veilText", "toast"
  ]

  static values = {
    writer: Boolean,
    folderId: String,
    folderName: String,
    uploadUrl: String,
    moveUrl: String,
    trashUrl: String,
    maxSize: Number,
    previousUrl: String,
    nextUrl: String
  }

  connect() {
    this.selection = new Map()
    this.dragging = null
    this.closeMenus = (event) => {
      this.element.querySelectorAll("details.ui-docs-menu[open]").forEach((menu) => {
        if (!menu.contains(event.target)) menu.open = false
      })
    }
    document.addEventListener("click", this.closeMenus)
  }

  disconnect() {
    document.removeEventListener("click", this.closeMenus)
    clearTimeout(this.veilTimer)
  }

  // --- Sélection ---------------------------------------------------------

  toggle(event) {
    const item = event.target.closest("[data-kind]")
    if (!item) return
    const key = `${item.dataset.kind}:${item.dataset.id}`
    if (event.target.checked) {
      this.selection.set(key, { kind: item.dataset.kind, id: item.dataset.id, name: item.dataset.name })
    } else {
      this.selection.delete(key)
    }
    item.classList.toggle("is-selected", event.target.checked)
    this.refreshSelection()
  }

  toggleAll(event) {
    this.itemTargets.filter((item) => item.dataset.kind === "file").forEach((item) => {
      const box = item.querySelector("input[type=checkbox]")
      if (box && box.checked !== event.target.checked) {
        box.checked = event.target.checked
        this.toggle({ target: box })
      }
    })
  }

  clearSelection() {
    if (this.element.querySelector("dialog[open]")) return
    this.itemTargets.forEach((item) => {
      item.classList.remove("is-selected")
      const box = item.querySelector("input[type=checkbox]")
      if (box) box.checked = false
    })
    if (this.hasSelectAllTarget) this.selectAllTarget.checked = false
    this.selection.clear()
    this.refreshSelection()
  }

  refreshSelection() {
    if (!this.hasSelectionBarTarget) return
    const count = this.selection.size
    this.selectionBarTarget.hidden = count === 0
    this.selectionCountTarget.textContent = count > 1 ? `${count} éléments choisis` : "1 élément choisi"
    this.element.classList.toggle("is-selecting", count > 0)
  }

  selectedItems() {
    return Array.from(this.selection.values())
  }

  // --- Glisser-déposer entre dossiers ------------------------------------

  dragStart(event) {
    if (!this.writerValue) return
    const item = event.currentTarget
    const key = `${item.dataset.kind}:${item.dataset.id}`
    const items = this.selection.has(key)
      ? this.selectedItems()
      : [{ kind: item.dataset.kind, id: item.dataset.id, name: item.dataset.name }]
    this.dragging = items
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData(INTERNAL, JSON.stringify(items))
    event.dataTransfer.setData("text/plain", items.map((i) => i.name).join("\n"))

    const ghost = document.createElement("div")
    ghost.className = "ui-docs-ghost"
    ghost.textContent = items.length > 1 ? `${items.length} éléments` : items[0].name
    document.body.appendChild(ghost)
    event.dataTransfer.setDragImage(ghost, 16, 16)
    setTimeout(() => ghost.remove(), 0)

    requestAnimationFrame(() => {
      this.itemTargets.forEach((el) => {
        if (items.some((i) => i.kind === el.dataset.kind && i.id === el.dataset.id)) el.classList.add("is-dragging")
      })
      this.element.classList.add("is-dragging-items")
    })
  }

  dragEnd() {
    this.dragging = null
    this.itemTargets.forEach((el) => el.classList.remove("is-dragging"))
    this.dropTargets.forEach((el) => el.classList.remove("is-over"))
    this.element.classList.remove("is-dragging-items")
  }

  dropOver(event) {
    const target = event.currentTarget
    if (this.dragging) {
      // Un dossier ne se dépose pas sur lui-même.
      if (this.dragging.some((i) => i.kind === "folder" && i.id === target.dataset.folderId)) return
      event.preventDefault()
      event.dataTransfer.dropEffect = "move"
      target.classList.add("is-over")
    } else if (this.hasFiles(event) && this.writerValue) {
      event.preventDefault()
      event.stopPropagation()
      event.dataTransfer.dropEffect = "copy"
      target.classList.add("is-over")
      this.showVeil(this.targetLabel(target))
    }
  }

  dropLeave(event) {
    const target = event.currentTarget
    if (event.relatedTarget && target.contains(event.relatedTarget)) return
    target.classList.remove("is-over")
  }

  dropOn(event) {
    const target = event.currentTarget
    target.classList.remove("is-over")
    const folderId = target.dataset.folderId || "root"
    if (this.dragging) {
      event.preventDefault()
      event.stopPropagation()
      const items = this.dragging
      this.dragEnd()
      if (items.some((i) => i.kind === "folder" && i.id === folderId)) return
      this.move(items, folderId)
    } else if (this.hasFiles(event) && this.writerValue) {
      event.preventDefault()
      event.stopPropagation()
      this.hideVeil()
      this.upload(event.dataTransfer.files, folderId, this.targetLabel(target))
    }
  }

  targetLabel(target) {
    if (target.dataset.folderId === "root") return "Documents"
    const name = target.dataset.name || target.textContent.trim().split("\n")[0].trim()
    return `« ${name} »`
  }

  // --- Fichiers venus du bureau ------------------------------------------

  hasFiles(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  osDragEnter(event) {
    if (this.dragging || !this.writerValue || !this.hasFiles(event)) return
    event.preventDefault()
    this.showVeil(this.folderNameValue)
  }

  osDragOver(event) {
    if (this.dragging || !this.writerValue || !this.hasFiles(event)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
    this.showVeil(this.folderNameValue)
  }

  osDragLeave() {
    // Le voile se retire de lui-même quand plus rien ne survole la page
    // (`showVeil` relance la minuterie à chaque `dragover`).
  }

  osDrop(event) {
    if (this.dragging || !this.writerValue || !this.hasFiles(event)) return
    event.preventDefault()
    this.hideVeil()
    this.upload(event.dataTransfer.files, this.folderIdValue, this.folderNameValue)
  }

  showVeil(label) {
    if (!this.hasVeilTarget) return
    this.veilTextTarget.textContent = `Dépose pour envoyer dans ${label}`
    this.veilTarget.hidden = false
    clearTimeout(this.veilTimer)
    this.veilTimer = setTimeout(() => this.hideVeil(), 180)
  }

  hideVeil() {
    clearTimeout(this.veilTimer)
    if (this.hasVeilTarget) this.veilTarget.hidden = true
    this.dropTargets.forEach((el) => el.classList.remove("is-over"))
  }

  pick(event) {
    const files = event.target.files
    if (!files || files.length === 0) return
    this.upload(files, this.folderIdValue, this.folderNameValue)
    event.target.value = ""
  }

  upload(fileList, folderId, label) {
    const files = Array.from(fileList || [])
    if (files.length === 0) return
    const tooBig = files.filter((f) => f.size > this.maxSizeValue)
    const ok = files.filter((f) => f.size <= this.maxSizeValue)
    if (tooBig.length) {
      this.toast(`${tooBig.map((f) => f.name).join(", ")} : trop lourd (${Math.round(this.maxSizeValue / 1048576)} Mo au plus par fichier).`)
    }
    if (ok.length === 0) return

    const data = new FormData()
    data.append("folder_id", folderId === "root" ? "" : folderId)
    ok.forEach((file) => data.append("files[]", file, file.name))
    const total = ok.reduce((sum, f) => sum + f.size, 0)

    this.uploadPanelTarget.hidden = false
    this.uploadTitleTarget.textContent = ok.length > 1 ? `Envoi de ${ok.length} fichiers dans ${label}…` : `Envoi de ${ok[0].name}…`
    this.uploadBarTarget.style.width = "0%"
    this.uploadDetailTarget.textContent = this.humanSize(total)

    const xhr = new XMLHttpRequest()
    xhr.open("POST", this.uploadUrlValue)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.setRequestHeader("X-CSRF-Token", this.csrfToken())
    xhr.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable) return
      const pct = Math.round((event.loaded / event.total) * 100)
      this.uploadBarTarget.style.width = `${pct}%`
      this.uploadDetailTarget.textContent = `${this.humanSize(event.loaded)} sur ${this.humanSize(event.total)}`
    })
    xhr.addEventListener("load", () => {
      let body = {}
      try { body = JSON.parse(xhr.responseText || "{}") } catch (_) { body = {} }
      if (xhr.status === 413) {
        this.uploadPanelTarget.hidden = true
        this.toast("Le serveur a refusé un envoi aussi lourd : essaie avec moins de fichiers à la fois.")
        return
      }
      this.uploadTitleTarget.textContent = "C’est envoyé."
      const here = String(folderId) === String(this.folderIdValue)
      const url = new URL(window.location.href)
      if (here && body.ids && body.ids.length) url.searchParams.set("nouveaux", body.ids.join(","))
      this.visit(url.toString())
    })
    xhr.addEventListener("error", () => {
      this.uploadPanelTarget.hidden = true
      this.toast("L’envoi n’a pas abouti (connexion coupée ?). Réessaie.")
    })
    xhr.send(data)
  }

  // --- Gestes ----------------------------------------------------------------

  async move(items, folderId) {
    const data = new FormData()
    data.append("target_folder_id", folderId)
    this.appendIds(data, items)
    await this.send("PATCH", this.moveUrlValue, data)
  }

  trashOne({ params }) {
    this.trash([{ kind: params.kind, id: String(params.id), name: params.name }])
  }

  trashSelection() {
    this.trash(this.selectedItems())
  }

  async trash(items) {
    if (items.length === 0) return
    const data = new FormData()
    this.appendIds(data, items)
    await this.send("POST", this.trashUrlValue, data)
  }

  appendIds(data, items) {
    items.forEach((item) => data.append(item.kind === "folder" ? "folder_ids[]" : "file_ids[]", item.id))
  }

  async send(method, url, data) {
    try {
      const response = await fetch(url, {
        method,
        body: data,
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken() },
        credentials: "same-origin"
      })
      const body = await response.json().catch(() => ({}))
      if (response.ok) {
        this.visit(body.location || window.location.href)
      } else {
        this.toast(body.error || "Ce geste n’a pas abouti.")
      }
    } catch (_) {
      this.toast("Pas de réponse du serveur. Réessaie.")
    }
  }

  // --- Fenêtres --------------------------------------------------------------

  newFolder() {
    const input = this.folderDialogTarget.querySelector("input[type=text]")
    input.value = ""
    this.folderDialogTarget.showModal()
    input.focus()
  }

  rename({ params }) {
    this.closeAllMenus()
    const input = this.renameInputTarget
    this.renameFormTarget.action = params.url
    input.name = `${params.kind}[name]`
    input.value = params.name
    this.renameLabelTarget.textContent = params.kind === "folder" ? "Nouveau nom du dossier" : "Nouveau nom du fichier"
    this.renameHintTarget.hidden = params.kind !== "file"
    this.renameDialogTarget.showModal()
    input.focus()
    // Le nom sans l'extension est présélectionné : on retape le nom, pas le « .pdf ».
    const dot = params.kind === "file" ? params.name.lastIndexOf(".") : -1
    input.setSelectionRange(0, dot > 0 ? dot : params.name.length)
  }

  moveOne({ params }) {
    this.openMove([{ kind: params.kind, id: String(params.id), name: params.name }])
  }

  moveSelection() {
    this.openMove(this.selectedItems())
  }

  openMove(items) {
    if (items.length === 0) return
    this.closeAllMenus()
    const movedFolders = items.filter((i) => i.kind === "folder").map((i) => i.id)
    // La liste des dossiers, sans ceux qu'on déplace ni leurs sous-dossiers.
    const select = this.moveSelectTarget
    select.innerHTML = ""
    this.moveOptionsTarget.content.querySelectorAll("option").forEach((option) => {
      const path = (option.dataset.path || "").split("/").filter(Boolean)
      if (movedFolders.some((id) => path.includes(id))) return
      select.appendChild(option.cloneNode(true))
    })
    select.value = ""
    select.dispatchEvent(new Event("change", { bubbles: true }))

    this.moveIdsTarget.innerHTML = ""
    items.forEach((item) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = item.kind === "folder" ? "folder_ids[]" : "file_ids[]"
      input.value = item.id
      this.moveIdsTarget.appendChild(input)
    })
    this.moveWhatTarget.textContent = items.length > 1 ? `${items.length} éléments choisis` : `« ${items[0].name} »`
    this.moveDialogTarget.showModal()
    const search = this.moveDialogTarget.querySelector("[data-searchable-select-target=input]")
    if (search) search.focus()
  }

  closeDialog(event) {
    event.target.closest("dialog")?.close()
  }

  // Un clic sur le fond (hors de la boîte) ferme la fenêtre.
  backdrop(event) {
    if (event.target === event.currentTarget) event.currentTarget.close()
  }

  closeAllMenus() {
    this.element.querySelectorAll("details.ui-docs-menu[open]").forEach((menu) => { menu.open = false })
  }

  menuToggle(event) {
    if (!event.target.open) return
    this.element.querySelectorAll("details.ui-docs-menu[open]").forEach((menu) => {
      if (menu !== event.target) menu.open = false
    })
  }

  // L'arbre de gauche : déplier, replier.
  twist(event) {
    const li = event.currentTarget.closest("li")
    const group = li.querySelector(":scope > div[hidden], :scope > div:not(.ui-docs-node-w)")
    if (!group) return
    const open = group.hidden
    group.hidden = !open
    li.setAttribute("aria-expanded", String(open))
  }

  // ← → sur l'aperçu d'un fichier : le voisin du même dossier.
  arrowKeys(event) {
    if (event.defaultPrevented || event.altKey || event.metaKey || event.ctrlKey) return
    if (event.target.closest("input, textarea, select, [contenteditable], iframe, video, audio")) return
    if (document.querySelector("dialog[open]")) return
    if (event.key === "ArrowLeft" && this.previousUrlValue) this.visit(this.previousUrlValue)
    if (event.key === "ArrowRight" && this.nextUrlValue) this.visit(this.nextUrlValue)
  }

  // --- Outils ------------------------------------------------------------------

  visit(url) {
    if (window.Turbo) {
      window.Turbo.visit(url, { action: "replace" })
    } else {
      window.location.href = url
    }
  }

  toast(message) {
    if (!this.hasToastTarget) { console.warn(message); return }
    this.toastTarget.textContent = message
    this.toastTarget.hidden = false
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => { this.toastTarget.hidden = true }, 6000)
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  humanSize(bytes) {
    if (bytes < 1024) return `${bytes} o`
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(0)} ko`
    return `${(bytes / 1048576).toFixed(1).replace(".", ",")} Mo`
  }
}
