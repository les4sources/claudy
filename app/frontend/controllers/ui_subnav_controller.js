import { Controller } from "@hotwired/stimulus"

// Sous-navigation d'une section dans la nouvelle interface (Michael
// 2026-10-24) : UNE ligne, sans barre de défilement. Les entrées qui ne
// tiennent pas passent, depuis la fin, dans un bouton « Plus ▾ » ; l'entrée
// active reste toujours visible. Recalculé à chaque changement de largeur.
//
// Les vues des sous-navigations (`layouts/components/_subnavs`) ne changent
// pas : on lit la première liste de chaque <nav>, et un groupe déroulant (la
// Comptabilité) passe dans « Plus » avec son titre et ses entrées.
const ACTIVE = "bg-teal-100"

export default class extends Controller {
  connect() {
    this.lists = [...this.element.querySelectorAll("nav ul")].filter((ul) => !ul.parentElement.closest("ul"))
    this.lists.forEach((ul) => this.prepare(ul))
    this.observer = new ResizeObserver(() => this.fitAll())
    this.lists.forEach((ul) => this.observer.observe(ul.parentElement))
    document.fonts?.ready.then(() => this.fitAll())
    this.onClick = (event) => this.closeOutside(event)
    this.onKey = (event) => { if (event.key === "Escape") this.closeAll() }
    this.beforeCache = () => this.closeAll()
    document.addEventListener("click", this.onClick)
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.fitAll()
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  prepare(ul) {
    ul.classList.add("ui-subnav-list")
    const more = document.createElement("li")
    more.className = "ui-subnav-more"
    more.hidden = true
    more.innerHTML = `<button type="button" aria-expanded="false" aria-haspopup="true">Plus <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg></button><div class="ui-subnav-menu" hidden></div>`
    more.querySelector("button").addEventListener("click", () => this.toggle(more))
    ul.appendChild(more)
  }

  fitAll() {
    this.lists.forEach((ul) => this.fit(ul))
  }

  fit(ul) {
    const more = ul.querySelector(":scope > .ui-subnav-more")
    const items = [...ul.children].filter((li) => li !== more)
    items.forEach((li) => { li.hidden = false })
    more.hidden = true
    this.close(more)
    if (!this.overflows(ul)) return

    more.hidden = false
    const hidden = []
    for (const li of [...items].reverse()) {
      if (!this.overflows(ul)) break
      if (li.querySelector(`:scope > .${ACTIVE}`)) continue
      li.hidden = true
      hidden.unshift(li)
    }
    this.fill(more.querySelector(".ui-subnav-menu"), hidden)
  }

  overflows(ul) {
    const last = [...ul.children].filter((li) => !li.hidden).pop()
    return last && last.getBoundingClientRect().right > ul.getBoundingClientRect().right + 1
  }

  fill(menu, items) {
    menu.replaceChildren()
    items.forEach((li) => {
      const group = li.querySelector(":scope > ul")
      if (group) {
        const title = document.createElement("p")
        title.textContent = li.querySelector(":scope > button")?.textContent.trim() || ""
        menu.appendChild(title)
        group.querySelectorAll("a").forEach((link) => menu.appendChild(this.copy(link)))
      } else {
        const link = li.querySelector("a")
        if (link) menu.appendChild(this.copy(link))
      }
    })
  }

  copy(link) {
    const item = document.createElement("a")
    item.href = link.href
    item.textContent = link.querySelector("span")?.textContent.trim() || link.textContent.trim()
    if (link.classList.contains(ACTIVE)) item.setAttribute("aria-current", "page")
    return item
  }

  toggle(more) {
    const button = more.querySelector("button")
    const open = button.getAttribute("aria-expanded") !== "true"
    this.closeAll()
    if (open) {
      button.setAttribute("aria-expanded", "true")
      more.querySelector(".ui-subnav-menu").hidden = false
    }
  }

  close(more) {
    more.querySelector("button").setAttribute("aria-expanded", "false")
    more.querySelector(".ui-subnav-menu").hidden = true
  }

  closeAll() {
    this.element.querySelectorAll(".ui-subnav-more").forEach((more) => this.close(more))
  }

  closeOutside(event) {
    if (!event.target.closest(".ui-subnav-more")) this.closeAll()
  }
}
