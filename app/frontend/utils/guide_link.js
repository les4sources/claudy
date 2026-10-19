import { Node, mergeAttributes, nodeInputRule } from "@tiptap/core"

// Un lien vers une autre page du Guide, dans l'éditeur (Michael, 2026-10-19).
// En Markdown : `[[Titre]]` ou `[[Titre|texte affiché]]`, que le serveur
// transforme en lien (`Guide::Markdown`). Dans l'éditeur, c'est une étiquette
// insécable : sans ce nœud, l'éditeur réécrirait les crochets en `\[\[`.
const SOURCE = /^\[\[([^[\]|\n]+?)(?:\|([^[\]\n]+?))?\]\]/
const TYPED = /\[\[([^[\]|\n]+?)(?:\|([^[\]\n]+?))?\]\]$/

const attributesFrom = (match) => ({ title: match[1].trim(), label: match[2]?.trim() || null })

export const GuideLink = Node.create({
  name: "guideLink",
  group: "inline",
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      title: {
        default: "",
        parseHTML: (element) => element.getAttribute("data-title"),
        renderHTML: (attributes) => ({ "data-title": attributes.title }),
      },
      label: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-label"),
        renderHTML: (attributes) => (attributes.label ? { "data-label": attributes.label } : {}),
      },
    }
  },

  parseHTML() {
    return [{ tag: "span[data-guide-link]" }]
  },

  renderHTML({ node, HTMLAttributes }) {
    return [
      "span",
      mergeAttributes(HTMLAttributes, {
        "data-guide-link": "",
        class: "guide-wikilink-node",
        title: `Lien vers la page « ${node.attrs.title} »`,
      }),
      node.attrs.label || node.attrs.title,
    ]
  },

  renderText({ node }) {
    return node.attrs.label || node.attrs.title
  },

  markdownTokenName: "guideLink",
  markdownTokenizer: {
    name: "guideLink",
    level: "inline",
    start: (src) => src.indexOf("[["),
    tokenize(src) {
      const match = SOURCE.exec(src)
      if (!match) return undefined
      return { type: "guideLink", raw: match[0], ...attributesFrom(match) }
    },
  },

  parseMarkdown(token) {
    return { type: "guideLink", attrs: { title: token.title, label: token.label } }
  },

  renderMarkdown(node) {
    const { title, label } = node.attrs || {}
    return label ? `[[${title}|${label}]]` : `[[${title}]]`
  },

  // `[[Titre]]` tapé en entier devient l'étiquette.
  addInputRules() {
    return [nodeInputRule({ find: TYPED, type: this.type, getAttributes: attributesFrom })]
  },
})

// « Note de Frais » trouve « note de frais » : ni majuscules ni accents.
export const normalizeTitle = (text) =>
  text
    .replace(/[’‘]/g, "'")
    .replace(/[“”]/g, '"')
    .normalize("NFD")
    .replace(/\p{Mn}/gu, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim()
