import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"

// Attaché au conteneur d'un éditeur Trix (ActionText).
// Quand on colle du texte brut qui ressemble à du Markdown, on le convertit en
// HTML pour qu'il arrive mis en forme dans l'éditeur, au lieu d'apparaître avec
// les caractères Markdown bruts (#, *, -, etc.).
//
// Si le presse-papiers contient déjà du HTML (copie depuis une page web, Word…),
// on laisse Trix gérer le collage riche normalement.
export default class extends Controller {
  connect() {
    this.editorElement = this.element.querySelector("trix-editor")
    if (!this.editorElement) return

    this.onPaste = this.onPaste.bind(this)
    // En phase de capture pour passer avant le gestionnaire de collage de Trix.
    this.editorElement.addEventListener("paste", this.onPaste, true)
  }

  disconnect() {
    if (this.editorElement) {
      this.editorElement.removeEventListener("paste", this.onPaste, true)
    }
  }

  onPaste(event) {
    const clipboard = event.clipboardData
    if (!clipboard) return

    // Collage déjà riche → on laisse Trix faire.
    if (Array.from(clipboard.types).includes("text/html")) return

    const text = clipboard.getData("text/plain")
    if (!text || !this.looksLikeMarkdown(text)) return

    event.preventDefault()

    const html = marked.parse(text, { gfm: true, breaks: true }).trim()
    this.editorElement.editor.insertHTML(html)
  }

  // Heuristique : ne convertir que si le texte contient des marqueurs Markdown
  // (titres, listes, citations, code, gras, liens). Le texte ordinaire reste
  // collé tel quel pour éviter d'insérer des blocs intempestifs.
  looksLikeMarkdown(text) {
    return /(^|\n)\s{0,3}(#{1,6}\s|[-*+]\s|\d+\.\s|>\s|```)|`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|\[[^\]]+\]\([^)]+\)/.test(
      text
    )
  }
}
