import { Controller } from '@hotwired/stimulus';

// L'autocomplétion de l'espèce et de la variété sur la fiche plante (epic #348,
// phase 7). Un champ texte libre : on propose les existantes, et « Créer
// “Néflier” » quand rien ne correspond exactement. Rien n'est créé ici — le
// serveur résout le NOM à l'enregistrement (`find_or_create_by_name!`), donc un
// nom tapé sans passer par la liste marche aussi, et le formulaire reste
// soumissible sans JavaScript.
//
// Deux instances sur la fiche : `kind` = `species` (GET /map/species.json?q=)
// et `variety` (GET /map/species/:id/varieties.json?q=, `__ID__` dans l'URL).
// Quand l'espèce change, elle l'annonce (`plant-autocomplete:picked`) et la
// variété se recale sur elle ; une espèce nouvelle n'a pas encore de variétés.
export default class extends Controller {
  static targets = ['input', 'list', 'hint'];

  static values = {
    url: String,
    kind: { type: String, default: 'species' },
    scopeId: Number,
  };

  connect() {
    this.results = [];
    this.options = [];
    this.activeIndex = -1;
    this.requestId = 0;
    this.debounce = null;
    this.initialHint = this.hasHintTarget ? this.hintTarget.textContent : '';
  }

  disconnect() {
    clearTimeout(this.debounce);
    clearTimeout(this.closeTimer);
  }

  // Frappe ou focus : on interroge le serveur, un peu après la dernière touche.
  search(event) {
    clearTimeout(this.debounce);
    if (event?.type === 'input') this.announceTyped();
    this.debounce = setTimeout(() => this.fetchResults(), event?.type === 'focus' ? 0 : 150);
  }

  async fetchResults() {
    const url = this.searchUrl();
    if (!url) {
      this.render([]);
      return;
    }
    const requestId = ++this.requestId;
    try {
      const response = await fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' });
      if (!response.ok || requestId !== this.requestId) return;
      this.results = await response.json();
      // Le nom tapé correspond peut-être à une existante que la recherche
      // précédente ne contenait pas encore.
      if (this.inputTarget.value.trim()) this.announceTyped();
      if (document.activeElement === this.inputTarget) this.render(this.results);
    } catch {
      // Réseau de terrain : le champ reste un champ texte, le serveur créera.
    }
  }

  searchUrl() {
    const query = this.inputTarget.value.trim();
    let base = this.urlValue;
    if (this.kindValue === 'variety') {
      if (!this.scopeIdValue) return null;
      base = base.replace('__ID__', encodeURIComponent(this.scopeIdValue));
    }
    const separator = base.includes('?') ? '&' : '?';
    return query ? `${base}${separator}q=${encodeURIComponent(query)}` : base;
  }

  render(results) {
    const query = this.inputTarget.value.trim();
    const exact = results.some((item) => item.name.toLowerCase() === query.toLowerCase());
    this.options = results.map((item) => ({ ...item, create: false }));
    if (query && !exact) this.options.push({ id: null, name: query, create: true });

    this.listTarget.innerHTML = '';
    this.options.forEach((option, index) => {
      const li = document.createElement('li');
      li.id = `${this.listTarget.id}-${index}`;
      li.setAttribute('role', 'option');
      li.className = 'flex min-h-[44px] cursor-pointer items-center gap-2 px-3 py-2 text-sm text-stone-700';
      li.dataset.index = index;
      if (option.create) {
        li.classList.add('border-t', 'border-stone-100', 'font-medium', 'text-forest');
        li.textContent = `Créer « ${option.name} »`;
      } else {
        const name = document.createElement('span');
        name.textContent = option.name;
        li.appendChild(name);
        if (option.latin_name) {
          const latin = document.createElement('span');
          latin.className = 'truncate text-xs italic text-stone-400';
          latin.textContent = option.latin_name;
          li.appendChild(latin);
        }
      }
      // `mousedown` et non `click` : le champ perdrait le focus (et la liste se
      // fermerait) avant le clic.
      li.addEventListener('mousedown', (event) => {
        event.preventDefault();
        this.pick(index);
      });
      this.listTarget.appendChild(li);
    });

    this.activeIndex = -1;
    this.toggle(this.options.length > 0);
  }

  navigate(event) {
    const open = !this.listTarget.classList.contains('hidden');
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      if (!open) return;
      event.preventDefault();
      const step = event.key === 'ArrowDown' ? 1 : -1;
      this.activeIndex = (this.activeIndex + step + this.options.length) % this.options.length;
      this.highlight();
    } else if (event.key === 'Enter' && open && this.activeIndex >= 0) {
      // Entrée choisit l'option en surbrillance, sans soumettre la fiche.
      event.preventDefault();
      this.pick(this.activeIndex);
    } else if (event.key === 'Escape' && open) {
      event.preventDefault();
      this.toggle(false);
    }
  }

  highlight() {
    Array.from(this.listTarget.children).forEach((li, index) => {
      const active = index === this.activeIndex;
      li.classList.toggle('bg-forest-tint', active);
      li.setAttribute('aria-selected', active ? 'true' : 'false');
      if (active) li.scrollIntoView({ block: 'nearest' });
    });
    const active = this.listTarget.children[this.activeIndex];
    if (active) this.inputTarget.setAttribute('aria-activedescendant', active.id);
    else this.inputTarget.removeAttribute('aria-activedescendant');
  }

  pick(index) {
    const option = this.options[index];
    if (!option) return;
    this.inputTarget.value = option.name;
    this.toggle(false);
    this.setHint(option);
    this.dispatch('picked', { detail: { kind: this.kindValue, id: option.id, name: option.name } });
  }

  // Un nom tapé à la main : c'est une existante si la dernière recherche la
  // contient à l'identique, sinon une nouvelle (créée à l'enregistrement).
  announceTyped() {
    const query = this.inputTarget.value.trim();
    const match = this.results.find((item) => item.name.toLowerCase() === query.toLowerCase());
    const id = match?.id || null;
    this.setHint(match || (query ? { id: null, name: query, create: true } : null));
    if (id === this.announcedId && query === this.announcedName) return;
    this.announcedId = id;
    this.announcedName = query;
    this.dispatch('picked', { detail: { kind: this.kindValue, id, name: query } });
  }

  setHint(option) {
    if (!this.hasHintTarget) return;
    if (!option) {
      this.hintTarget.textContent = '';
    } else if (option.create || option.id == null) {
      const what = this.kindValue === 'variety' ? 'Nouvelle variété' : 'Nouvelle espèce';
      this.hintTarget.textContent = `${what} : créée à l'enregistrement.`;
    } else {
      this.hintTarget.textContent = option.latin_name || '';
    }
    this.hintTarget.classList.toggle('italic', Boolean(option?.latin_name));
  }

  // La variété suit l'espèce annoncée par l'autre champ.
  rescope(event) {
    if (this.kindValue !== 'variety' || event.detail?.kind !== 'species') return;
    const id = event.detail.id || 0;
    if (id === this.scopeIdValue) return;
    this.scopeIdValue = id;
    this.results = [];
    if (this.hasHintTarget && this.inputTarget.value.trim()) {
      this.hintTarget.textContent = id ? '' : 'Nouvelle variété : créée avec l’espèce.';
    }
  }

  close() {
    // Laisse le temps à un `mousedown` sur une option d'arriver.
    clearTimeout(this.closeTimer);
    this.closeTimer = setTimeout(() => this.toggle(false), 120);
  }

  toggle(open) {
    this.listTarget.classList.toggle('hidden', !open);
    this.inputTarget.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (!open) {
      this.activeIndex = -1;
      this.inputTarget.removeAttribute('aria-activedescendant');
    }
  }
}
