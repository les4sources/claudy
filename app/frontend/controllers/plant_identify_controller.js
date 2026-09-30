import { Controller } from '@hotwired/stimulus';

// « Quelle est cette plante ? » sur la fiche plante. Les photos choisies partent
// en POST /map/plants/identify (Pl@ntNet) ; le serveur répond le fragment
// `plants/_identification`, inséré sous le bouton. « C'est elle » remplit le
// champ Espèce comme un choix de l'autocomplétion (la variété se recale), et
// apporte nom latin et famille pour une espèce encore inconnue du catalogue.
// « Non » écarte la proposition. Rien n'est enregistré ici : c'est le bouton
// de la fiche qui enregistre.
//
// Le champ fichier n'a pas de `name` : le formulaire de la fiche l'ignore, seules
// les cases « Joindre à la fiche » du fragment rejoignent la plante.
export default class extends Controller {
  static targets = ['input', 'label', 'results', 'latinName', 'family'];

  static values = { url: String };

  connect() {
    this.idleLabel = this.hasLabelTarget ? this.labelTarget.textContent : '';
    // Une espèce retapée à la main n'est plus celle de Pl@ntNet : son nom latin
    // ne doit pas partir avec.
    this.clearBotany = () => this.setBotany('', '');
    this.speciesInput?.addEventListener('input', this.clearBotany);
  }

  disconnect() {
    this.speciesInput?.removeEventListener('input', this.clearBotany);
  }

  get speciesInput() {
    return this.element.closest('form')?.querySelector('#plant_species_name');
  }

  async identify() {
    const files = Array.from(this.inputTarget.files || []);
    if (files.length === 0) return;

    const body = new FormData();
    files.forEach((file) => body.append('photos[]', file));
    this.busy(true);
    try {
      const response = await fetch(this.urlValue, {
        method: 'POST',
        body,
        credentials: 'same-origin',
        headers: {
          Accept: 'text/html',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
        },
      });
      this.resultsTarget.innerHTML = await response.text();
    } catch {
      this.resultsTarget.innerHTML =
        '<p class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-800" role="alert">' +
        'Réseau indisponible : réessayez, ou saisissez l’espèce à la main.</p>';
    } finally {
      this.busy(false);
      this.inputTarget.value = '';
    }
  }

  accept(event) {
    const card = event.currentTarget.closest('[data-plant-identify-target="proposal"]');
    if (!card) return;
    const input = this.speciesInput;
    const { name, latinName, family, speciesId } = card.dataset;

    if (input) {
      input.value = name;
      const id = speciesId ? Number(speciesId) : null;
      // Même annonce que l'autocomplétion : la variété se recale sur l'espèce.
      input.dispatchEvent(
        new CustomEvent('plant-autocomplete:picked', { bubbles: true, detail: { kind: 'species', id, name } }),
      );
      const hint = input
        .closest('[data-controller~="plant-autocomplete"]')
        ?.querySelector('[data-plant-autocomplete-target="hint"]');
      if (hint) {
        hint.textContent = id ? latinName : `Nouvelle espèce (${latinName}) : créée à l'enregistrement.`;
        hint.classList.toggle('italic', Boolean(id));
      }
    }
    this.setBotany(latinName || '', family || '');

    this.proposals.forEach((other) => {
      const chosen = other === card;
      other.classList.toggle('border-forest', chosen);
      other.classList.toggle('bg-forest-tint', chosen);
      other.hidden = !chosen;
      this.toggleChoice(other, !chosen);
    });
    this.toggleHeading(false);
  }

  reject(event) {
    const card = event.currentTarget.closest('[data-plant-identify-target="proposal"]');
    if (!card) return;
    card.dataset.rejected = 'true';
    card.hidden = true;
    const left = this.proposals.some((other) => !other.dataset.rejected);
    this.toggleHeading(left);
    const none = this.resultsTarget.querySelector('[data-plant-identify-target="none"]');
    if (none) none.classList.toggle('hidden', left);
  }

  // « Changer » : les propositions non refusées reviennent.
  reset() {
    this.proposals.forEach((card) => {
      card.classList.remove('border-forest', 'bg-forest-tint');
      card.hidden = Boolean(card.dataset.rejected);
      this.toggleChoice(card, true);
    });
    this.toggleHeading(true);
  }

  get proposals() {
    return Array.from(this.resultsTarget.querySelectorAll('[data-plant-identify-target="proposal"]'));
  }

  toggleChoice(card, open) {
    card.querySelector('[data-plant-identify-choice]')?.classList.toggle('hidden', !open);
    const chosen = card.querySelector('[data-plant-identify-chosen]');
    chosen?.classList.toggle('hidden', open);
    chosen?.classList.toggle('flex', !open);
  }

  toggleHeading(visible) {
    const heading = this.resultsTarget.querySelector('[data-plant-identify-target="heading"]');
    if (heading) heading.hidden = !visible;
  }

  setBotany(latinName, family) {
    if (this.hasLatinNameTarget) this.latinNameTarget.value = latinName;
    if (this.hasFamilyTarget) this.familyTarget.value = family;
  }

  busy(on) {
    this.inputTarget.disabled = on;
    if (this.hasLabelTarget) this.labelTarget.textContent = on ? 'Pl@ntNet regarde les photos…' : this.idleLabel;
    this.element.setAttribute('aria-busy', on ? 'true' : 'false');
  }
}
