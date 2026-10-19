import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Placeholder from "@tiptap/extension-placeholder"
import Image from "@tiptap/extension-image"
import { TableKit } from "@tiptap/extension-table"
import { TaskList, TaskItem } from "@tiptap/extension-list"
import { Markdown } from "@tiptap/markdown"
import { DirectUpload } from "@rails/activestorage"

// L'éditeur visuel du Guide des 4 Sources (2026-10-19). Il écrit du
// MARKDOWN dans le <textarea> du formulaire, qui reste la source de vérité :
// c'est lui qui est soumis, et c'est lui qu'on édite en mode « Markdown ».
//
// Les images sont téléversées tout de suite (Active Storage, upload direct) et
// insérées par leur adresse permanente
// `/rails/active_storage/blobs/redirect/<signed_id>/<nom>` ; à
// l'enregistrement, `Guide::SavePage` les rattache à la page.
//
// Le <textarea> n'est réécrit qu'après une vraie modification : ouvrir une
// page et l'enregistrer sans y toucher ne crée pas de version fantôme, même si
// l'éditeur aurait normalisé le Markdown autrement.
const COMMANDS = {
  paragraph: (chain) => chain.setParagraph(),
  h2: (chain) => chain.toggleHeading({ level: 2 }),
  h3: (chain) => chain.toggleHeading({ level: 3 }),
  bold: (chain) => chain.toggleBold(),
  italic: (chain) => chain.toggleItalic(),
  strike: (chain) => chain.toggleStrike(),
  code: (chain) => chain.toggleCode(),
  bulletList: (chain) => chain.toggleBulletList(),
  orderedList: (chain) => chain.toggleOrderedList(),
  taskList: (chain) => chain.toggleTaskList(),
  blockquote: (chain) => chain.toggleBlockquote(),
  table: (chain) => chain.insertTable({ rows: 3, cols: 3, withHeaderRow: true }),
  horizontalRule: (chain) => chain.setHorizontalRule(),
  undo: (chain) => chain.undo(),
  redo: (chain) => chain.redo(),
  addRowAfter: (chain) => chain.addRowAfter(),
  addColumnAfter: (chain) => chain.addColumnAfter(),
  deleteRow: (chain) => chain.deleteRow(),
  deleteColumn: (chain) => chain.deleteColumn(),
  deleteTable: (chain) => chain.deleteTable(),
}

const ACTIVE = {
  paragraph: (editor) => editor.isActive("paragraph"),
  h2: (editor) => editor.isActive("heading", { level: 2 }),
  h3: (editor) => editor.isActive("heading", { level: 3 }),
  bold: (editor) => editor.isActive("bold"),
  italic: (editor) => editor.isActive("italic"),
  strike: (editor) => editor.isActive("strike"),
  code: (editor) => editor.isActive("code"),
  bulletList: (editor) => editor.isActive("bulletList"),
  orderedList: (editor) => editor.isActive("orderedList"),
  taskList: (editor) => editor.isActive("taskList"),
  blockquote: (editor) => editor.isActive("blockquote"),
}

export default class extends Controller {
  static targets = ["editor", "source", "toolbar", "visualTools", "tableTools", "sourceToggle", "file", "status"]
  static values = { uploadUrl: String }

  connect() {
    this.sourceMode = false
    this.sourceTarget.hidden = true

    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [
        StarterKit.configure({
          heading: { levels: [2, 3, 4] },
          // Le soulignement n'existe pas en Markdown : il serait perdu à
          // l'enregistrement.
          underline: false,
          link: { openOnClick: false, autolink: true, defaultProtocol: "https" },
        }),
        Placeholder.configure({ placeholder: "Écris ici… Un titre, une liste, une image glissée depuis ton ordinateur." }),
        Image.configure({ inline: false, allowBase64: false }),
        TableKit.configure({ table: { resizable: false } }),
        TaskList,
        TaskItem.configure({ nested: true }),
        Markdown,
      ],
      content: this.sourceTarget.value || "",
      contentType: "markdown",
      editorProps: {
        attributes: { class: "prose prose-stone max-w-none focus:outline-none prose-a:text-emerald-700" },
        handlePaste: (_view, event) => this.handleFiles(event.clipboardData?.files),
        handleDrop: (view, event, _slice, moved) => {
          if (moved) return false
          const position = view.posAtCoords({ left: event.clientX, top: event.clientY })
          if (position) this.editor.commands.setTextSelection(position.pos)
          return this.handleFiles(event.dataTransfer?.files)
        },
      },
      onUpdate: () => {
        if (!this.loading) this.sourceTarget.value = this.editor.getMarkdown()
      },
      onTransaction: () => this.refreshToolbar(),
    })
    this.refreshToolbar()
  }

  disconnect() {
    this.editor?.destroy()
    this.editor = null
  }

  run({ params: { command } }) {
    const action = COMMANDS[command]
    if (!action || this.sourceMode) return
    action(this.editor.chain().focus()).run()
  }

  link() {
    if (this.sourceMode) return
    const previous = this.editor.getAttributes("link").href
    const url = window.prompt("Adresse du lien (laisser vide pour retirer le lien)", previous || "https://")
    if (url === null) return
    const chain = this.editor.chain().focus().extendMarkRange("link")
    if (url.trim() === "") chain.unsetLink().run()
    else chain.setLink({ href: url.trim() }).run()
  }

  // Bascule entre l'éditeur visuel et le Markdown brut.
  toggleSource() {
    this.sourceMode = !this.sourceMode
    if (this.sourceMode) {
      this.sourceTarget.hidden = false
      this.editorTarget.hidden = true
      this.sourceTarget.style.minHeight = `${Math.max(this.editorTarget.offsetHeight, 384)}px`
      this.sourceTarget.focus()
    } else {
      // Recharger l'éditeur depuis le Markdown tapé, SANS réécrire celui-ci :
      // ce qui a été tapé à la main est ce qui sera enregistré.
      this.loading = true
      this.editor.commands.setContent(this.sourceTarget.value || "", { contentType: "markdown" })
      this.loading = false
      this.sourceTarget.hidden = true
      this.editorTarget.hidden = false
      this.editor.commands.focus()
    }
    this.refreshToolbar()
  }

  pickImage() {
    this.fileTarget.click()
  }

  upload() {
    this.handleFiles(this.fileTarget.files)
    this.fileTarget.value = ""
  }

  dragOver(event) {
    if (!Array.from(event.dataTransfer?.types || []).includes("Files")) return
    event.preventDefault()
    this.element.classList.add("is-dragging")
  }

  dragLeave() {
    this.element.classList.remove("is-dragging")
  }

  drop(event) {
    this.element.classList.remove("is-dragging")
    // Déposée sur le Markdown brut : l'éditeur visuel ne la voit pas passer.
    if (this.sourceMode && event.dataTransfer?.files?.length) {
      event.preventDefault()
      this.handleFiles(event.dataTransfer.files)
    }
  }

  // Rend `true` quand il y avait des images à prendre en charge (l'éditeur
  // n'a alors rien d'autre à faire du collage ou du dépôt).
  handleFiles(fileList) {
    const images = Array.from(fileList || []).filter((file) => file.type.startsWith("image/"))
    images.forEach((file) => this.uploadImage(file))
    return images.length > 0
  }

  uploadImage(file) {
    this.setStatus(`Envoi de « ${file.name} »…`)
    new DirectUpload(file, this.uploadUrlValue).create((error, blob) => {
      if (error) {
        this.setStatus(`L'image « ${file.name} » n'a pas pu être envoyée.`, true)
        return
      }
      const src = `/rails/active_storage/blobs/redirect/${blob.signed_id}/${encodeURIComponent(blob.filename)}`
      const alt = file.name.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ")
      if (this.sourceMode) {
        this.insertInSource(`\n![${alt}](${src})\n`)
      } else {
        this.editor.chain().focus().setImage({ src, alt }).run()
      }
      this.setStatus(`Image « ${file.name} » ajoutée.`)
    })
  }

  insertInSource(text) {
    const field = this.sourceTarget
    const start = field.selectionStart ?? field.value.length
    field.setRangeText(text, start, field.selectionEnd ?? start, "end")
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }

  setStatus(message, isError = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-red-600", isError)
  }

  refreshToolbar() {
    if (!this.editor) return
    this.toolbarTarget.querySelectorAll("[data-guide-editor-command-param]").forEach((button) => {
      const active = ACTIVE[button.dataset.guideEditorCommandParam]
      if (active) button.setAttribute("aria-pressed", String(!this.sourceMode && active(this.editor)))
    })
    this.visualToolsTarget.classList.toggle("opacity-40", this.sourceMode)
    this.visualToolsTarget.classList.toggle("pointer-events-none", this.sourceMode)
    this.tableToolsTarget.classList.toggle("hidden", this.sourceMode || !this.editor.isActive("table"))
    this.tableToolsTarget.classList.toggle("flex", !this.sourceMode && this.editor.isActive("table"))
    this.sourceToggleTarget.setAttribute("aria-pressed", String(this.sourceMode))
  }
}
