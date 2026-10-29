import { Controller } from '@hotwired/stimulus';

// La palette ⌘K (redesign, Michael 2026-10-29). ⌘K / Ctrl+K l'ouvre de
// partout, « Chercher… » et la loupe aussi. Chaque frappe (un court délai)
// demande les résultats à `searches#show`, un fragment HTML : la palette ne
// sait rien des séjours, elle pose ce que le serveur lui rend.
// Au clavier : ↑↓ choisit, ↵ ouvre, ⌘↵ / Ctrl+↵ ouvre dans un nouvel onglet,
// Échap referme (le <dialog> natif).
export default class extends Controller {
  static targets = ['dialog', 'input', 'results'];

  connect() {
    this.shortcut = this.shortcut.bind(this);
    this.beforeVisit = () => this.close();
    window.addEventListener('keydown', this.shortcut);
    document.addEventListener('turbo:before-visit', this.beforeVisit);
  }

  disconnect() {
    window.removeEventListener('keydown', this.shortcut);
    document.removeEventListener('turbo:before-visit', this.beforeVisit);
    clearTimeout(this.timer);
  }

  shortcut(event) {
    if ((event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      this.dialogTarget.open ? this.close() : this.open();
    }
  }

  open() {
    if (this.dialogTarget.open) return;
    this.dialogTarget.showModal();
    this.inputTarget.value = '';
    this.inputTarget.focus();
    this.fetch('');
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close();
  }

  closed() {
    clearTimeout(this.timer);
    this.request?.abort();
  }

  // Un clic sur le fond (le <dialog> lui-même, pas sa boîte) referme.
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close();
  }

  search() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.fetch(this.inputTarget.value), 140);
  }

  async fetch(query) {
    this.request?.abort();
    this.request = new AbortController();
    const url = new URL(this.resultsTarget.dataset.url, window.location.origin);
    url.searchParams.set('q', query.trim());
    try {
      const response = await fetch(url, { headers: { Accept: 'text/html' }, signal: this.request.signal });
      if (!response.ok) return;
      this.resultsTarget.innerHTML = await response.text();
      this.select(0);
    } catch (error) {
      if (error.name !== 'AbortError') {
        this.resultsTarget.innerHTML = '<p class="ui-cmd-empty">La recherche ne répond pas : vérifie le réseau.</p>';
      }
    }
  }

  key(event) {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      this.select(this.index + (event.key === 'ArrowDown' ? 1 : -1));
    } else if (event.key === 'Enter') {
      const item = this.items[this.index];
      if (!item) return;
      event.preventDefault();
      if (event.metaKey || event.ctrlKey) {
        window.open(item.href, '_blank', 'noopener');
      } else {
        this.close();
        window.Turbo.visit(item.href);
      }
    }
  }

  select(index) {
    const items = this.items;
    if (items.length === 0) {
      this.index = -1;
      this.inputTarget.removeAttribute('aria-activedescendant');
      return;
    }
    this.index = (index + items.length) % items.length;
    items.forEach((item, i) => item.setAttribute('aria-selected', i === this.index ? 'true' : 'false'));
    const current = items[this.index];
    this.inputTarget.setAttribute('aria-activedescendant', current.id);
    current.scrollIntoView({ block: 'nearest' });
  }

  get items() {
    return Array.from(this.resultsTarget.querySelectorAll('[data-command-item]'));
  }
}
