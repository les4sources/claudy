import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Placeholder from "@tiptap/extension-placeholder"

// TipTap rich-text editor that writes HTML into a hidden ActionText field.
// Replaces Trix for the agenda item "Fiche de préparation" only; the stored
// HTML lives in the same `agenda_item[description]` ActionText field, so
// persistence and rendering are unchanged.
//
// Markup (see agenda_items/_form):
//   div(data-controller="tiptap" data-tiptap-content-value="<stored html>")
//     .toolbar ... buttons with data-action="tiptap#toggleBold" etc.
//     div(data-tiptap-target="editor")
//     input(type="hidden" name="agenda_item[description]" data-tiptap-target="input")
export default class extends Controller {
  static targets = ["editor", "input"]
  static values = {
    placeholder: { type: String, default: "Contexte, questions à trancher, documents utiles…" },
  }

  connect() {
    // Initial content comes from the hidden ActionText field (correctly escaped
    // by Rails), never from a data attribute — rich-text HTML contains quotes
    // that would break an HTML attribute value.
    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [
        StarterKit.configure({ link: { openOnClick: false, autolink: true } }),
        Placeholder.configure({ placeholder: this.placeholderValue }),
      ],
      content: this.inputTarget.value || "",
      editorProps: {
        attributes: { class: "prose max-w-none focus:outline-none min-h-[10rem]" },
      },
      onUpdate: () => {
        this.inputTarget.value = this.editor.getHTML()
      },
    })

    // Seed the hidden field so submitting without edits still persists content.
    this.inputTarget.value = this.editor.getHTML()
  }

  disconnect() {
    if (this.editor) {
      this.editor.destroy()
      this.editor = null
    }
  }

  toggleBold(e) { e.preventDefault(); this.editor.chain().focus().toggleBold().run() }
  toggleItalic(e) { e.preventDefault(); this.editor.chain().focus().toggleItalic().run() }
  toggleHeading(e) { e.preventDefault(); this.editor.chain().focus().toggleHeading({ level: 3 }).run() }
  toggleBulletList(e) { e.preventDefault(); this.editor.chain().focus().toggleBulletList().run() }
  toggleOrderedList(e) { e.preventDefault(); this.editor.chain().focus().toggleOrderedList().run() }

  setLink(e) {
    e.preventDefault()
    const previous = this.editor.getAttributes("link").href
    const url = window.prompt("URL du lien", previous || "https://")
    if (url === null) return
    if (url === "") {
      this.editor.chain().focus().extendMarkRange("link").unsetLink().run()
      return
    }
    this.editor.chain().focus().extendMarkRange("link").setLink({ href: url }).run()
  }
}
