// L'espèce d'un relevé de biodiversité (epic #348, phase 13) : autocomplétion
// sur les noms communs DÉJÀ saisis au domaine (décision 9 : aucune source
// externe). Les suggestions remplissent un <datalist> ; choisir un nom connu
// complète le nom latin s'il est vide, et le règne s'il n'est pas encore choisi.

import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['common', 'latin', 'list'];
  static values = { url: String };

  connect() {
    this.suggestions = [];
  }

  disconnect() {
    clearTimeout(this.timer);
    this.abort?.abort();
  }

  search() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.fetchSuggestions(), 180);
  }

  async fetchSuggestions() {
    const q = this.commonTarget.value.trim();
    this.abort?.abort();
    this.abort = new AbortController();
    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set('q', q);
    const realm = this.checkedRealm();
    if (realm) url.searchParams.set('realm', realm);
    try {
      const response = await fetch(url, {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
        signal: this.abort.signal,
      });
      if (!response.ok) return;
      this.suggestions = await response.json();
      this.render();
    } catch (_error) {
      // Requête annulée par une frappe plus récente, ou hors ligne : la
      // saisie libre reste possible.
    }
  }

  render() {
    this.listTarget.replaceChildren(
      ...this.suggestions.map((s) => {
        const option = document.createElement('option');
        option.value = s.common;
        if (s.latin) option.label = s.latin;
        return option;
      })
    );
  }

  pick() {
    const value = this.commonTarget.value.trim().toLowerCase();
    const match = this.suggestions.find((s) => s.common.toLowerCase() === value);
    if (!match) return;
    if (this.hasLatinTarget && !this.latinTarget.value.trim() && match.latin) this.latinTarget.value = match.latin;
    if (!this.checkedRealm() && match.realm) {
      const radio = this.element.closest('form')?.querySelector(`[data-observation-realm="${match.realm}"]`);
      if (radio) radio.checked = true;
    }
  }

  checkedRealm() {
    return this.element.closest('form')?.querySelector('[data-observation-realm]:checked')?.value || null;
  }
}
