import { Controller } from "@hotwired/stimulus"

// Grille « calendrier de séjour » du funnel B2C /reservation : un tableau dont
// les colonnes sont les nuits du séjour et les lignes les hébergements (La
// Hulotte, La Chevêche, Le Grand-Duc). Chaque cellule est un <button> avec
// `aria-pressed`. La sélection d'un hébergement est EXCLUSIVE par nuit : une
// seule cellule peut être active dans une colonne donnée.
//
// À chaque toggle, on régénère intégralement le conteneur de champs cachés
// (`reservation[lodging_night_ids][]`) — exactement une entrée par nuit, vide
// pour les nuits sans hébergement — puis on émet un `change` bouillonnant. Ce
// `change` remonte au <form> parent porteur de
// `data-action="change->public--reservation-quote#refresh"` pour relancer le
// recalcul du devis.
export default class extends Controller {
  static targets = ["hiddenFields"]
  static values  = { nights: Number }

  // Restaure l'état depuis le rendu serveur (cellules `aria-pressed="true"`)
  // sans muter le DOM des cellules : on se contente de (re)construire les
  // champs cachés à partir de ce qui est déjà sélectionné.
  connect() {
    this.syncHiddenFields()
  }

  // Action — clic sur une cellule d'hébergement
  // (`click->public--stay-calendar#toggleLodging`). Sélection exclusive par
  // nuit : si la cellule est déjà active on la désactive ; sinon on désactive
  // l'éventuelle autre cellule active de la même colonne avant d'activer
  // celle-ci.
  toggleLodging(event) {
    event.preventDefault()
    const cell = event.currentTarget
    const nightIndex = cell.getAttribute("data-night-index")
    const isPressed = cell.getAttribute("aria-pressed") === "true"

    if (isPressed) {
      this.setCellState(cell, false)
    } else {
      const current = this.selectedCellForNight(nightIndex)
      // Désactive l'hébergement déjà choisi pour cette nuit (s'il y en a un et
      // que ce n'est pas la cellule cliquée) avant d'activer le nouveau.
      if (current && current !== cell) this.setCellState(current, false)
      this.setCellState(cell, true)
    }

    this.syncHiddenFields()
    this.dispatchChange()
  }

  // Retourne la cellule d'hébergement active (`aria-pressed="true"`) pour la
  // nuit donnée, ou null si aucune. La nuit est identifiée par la valeur exacte
  // de `data-night-index` (comparaison sur chaîne, telle que rendue par le
  // template), pour rester robuste aux index non contigus.
  selectedCellForNight(nightIndex) {
    const cells = this.lodgingCells()
    for (const cell of cells) {
      if (
        cell.getAttribute("data-night-index") === nightIndex &&
        cell.getAttribute("aria-pressed") === "true"
      ) {
        return cell
      }
    }
    return null
  }

  // Toutes les cellules d'hébergement de la grille
  // (`data-type="lodging"`), bornées au scope du controller.
  lodgingCells() {
    return this.element.querySelectorAll('[data-type="lodging"]')
  }

  // Classes identiques à celles du template Slim — source de vérité unique.
  // Le texte (✓ / vide) est mis à jour en même temps que les classes pour
  // éviter tout désynchronisation entre état visuel et contenu.
  setCellState(cell, selected) {
    const selectedClasses = ["bg-emerald-500", "border-emerald-500", "text-white", "shadow-sm"]
    const idleClasses = ["bg-white", "border-gray-200", "text-gray-300", "hover:border-emerald-400", "hover:bg-emerald-50"]

    cell.setAttribute("aria-pressed", selected ? "true" : "false")
    cell.textContent = selected ? "✓" : ""

    if (selected) {
      cell.classList.remove(...idleClasses)
      cell.classList.add(...selectedClasses)
    } else {
      cell.classList.remove(...selectedClasses)
      cell.classList.add(...idleClasses)
    }
  }

  // (Re)construit le conteneur de champs cachés : on vide entièrement puis on
  // recrée exactement N inputs (N = `nightsValue`), un par nuit dans l'ordre
  // 0..N-1. Chaque input porte le `value` de l'hébergement sélectionné pour
  // cette nuit, ou la chaîne vide sinon. Le serveur reçoit donc toujours un
  // tableau de longueur fixe, positionnel par nuit.
  syncHiddenFields() {
    if (!this.hasHiddenFieldsTarget) return

    // Indexe les sélections actives par nuit pour un accès en O(1). On garde la
    // dernière cellule active rencontrée par nuit ; l'invariant d'exclusivité
    // garantit qu'il n'y en a qu'une, mais cette tolérance évite tout état
    // incohérent si le rendu serveur en présentait deux.
    const selectionByNight = new Map()
    for (const cell of this.lodgingCells()) {
      if (cell.getAttribute("aria-pressed") !== "true") continue
      const nightIndex = cell.getAttribute("data-night-index")
      const lodgingId = cell.getAttribute("data-lodging-id")
      if (nightIndex === null) continue
      selectionByNight.set(nightIndex, lodgingId ?? "")
    }

    const container = this.hiddenFieldsTarget
    container.replaceChildren()

    // `nightsValue` est garanti Number par Stimulus (défaut 0 si l'attribut est
    // absent) ; on borne à un entier >= 0 pour ne jamais boucler sur NaN/négatif.
    const count = Number.isFinite(this.nightsValue) ? Math.max(0, Math.trunc(this.nightsValue)) : 0

    for (let night = 0; night < count; night += 1) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "reservation[lodging_night_ids][]"
      // La clé d'index est une chaîne (telle que rendue dans `data-night-index`).
      input.value = selectionByNight.get(String(night)) ?? ""
      container.appendChild(input)
    }
  }

  // Émet un `change` bouillonnant depuis l'élément du controller. Il remonte au
  // <form> parent (`change->public--reservation-quote#refresh`) pour déclencher
  // le recalcul du devis. On émet depuis `this.element` : le bubbling atteint le
  // formulaire ancêtre sans qu'on ait à le résoudre explicitement.
  dispatchChange() {
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
