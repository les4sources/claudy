# Remplacement de Flowbite JS par des contrôleurs Stimulus

**Date** : 2026-04-22
**Contexte** : l'application devient de plus en plus lente au fil des navigations. Investigation systématique : `flowbite/dist/flowbite.turbo.js` ré-exécute `initDropdowns`, `initTooltips`, `initPopovers`, etc. à chaque `turbo:load` sans dédupliquer ni détruire les instances précédentes. Résultat : accumulation de handlers `click` sur `document.body` et d'instances Popper.js qui grossit à chaque navigation.

## Objectif

Supprimer `flowbite` et `flowbite.turbo.js` de l'entrypoint JS. Remplacer les 4 comportements utilisés par des contrôleurs Stimulus qui nettoient proprement via `disconnect()`.

## Périmètre

### Inventaire des usages Flowbite dans le code

| Comportement Flowbite | Occurrences dans les vues | Action |
|---|---|---|
| `data-dropdown-toggle="id"` | `app/views/layouts/components/_navbar.html.slim` (menu "Accueil") | Nouveau `dropdown_controller.js` |
| `data-collapse-toggle="id"` | `app/views/layouts/components/_navbar.html.slim` (menu hamburger mobile) | Nouveau `collapse_controller.js` |
| `data-tooltip-target="id"` | `app/views/human_roles/_edit.html.slim`, `_day.html.slim`, `_human_role.html.slim` | Nouveau `tooltip_controller.js` |
| `data-popover-target="id"` + `data-popover-trigger="click"` | `app/views/pages/calendar.html.slim` (3 blocs), `app/views/shared/_popover_icon.html.erb` | Nouveau `popover_controller.js` |
| Modal, Tabs, Drawer, Dial, Accordion, Carousel, Dismiss | Aucun usage | Aucune action |
| Datepicker (`flowbite/dist/datepicker`) | `[datepicker]`, `[inline-datepicker]`, `[date-rangepicker]` dans les formulaires | **Conservé** tel quel |

### Fichiers HTML/Slim à modifier

- `app/views/layouts/components/_navbar.html.slim` — ajouter `data-controller` sur bouton "Accueil" et bouton hamburger ; renommer les data-attrs Flowbite vers le format Stimulus values.
- `app/views/pages/calendar.html.slim` — 3 triggers popover : ajouter `data-controller="popover"` et renommer les data-attrs.
- `app/views/shared/_popover_icon.html.erb` — idem.
- `app/views/human_roles/_edit.html.slim`, `_day.html.slim`, `_human_role.html.slim` — triggers tooltip : ajouter `data-controller="tooltip"` et renommer les data-attrs.

### Fichiers JS à créer

- `app/frontend/controllers/dropdown_controller.js`
- `app/frontend/controllers/collapse_controller.js`
- `app/frontend/controllers/tooltip_controller.js`
- `app/frontend/controllers/popover_controller.js`

Ces contrôleurs sont chargés automatiquement par `stimulus-vite-helpers` via le glob existant dans `app/frontend/utils/setupStimulus.js` (lignes 24-27).

### Fichiers JS à modifier

- `app/frontend/entrypoints/application.js` — retirer `import 'flowbite'` et `import 'flowbite/dist/flowbite.turbo.js'` ; **conserver** `import 'flowbite/dist/datepicker'` et `import '../utils/datepicker.turbo.min.js'`.
- `app/frontend/entrypoints/public.js` — mêmes retraits que `application.js`. Vérifié : aucun `data-dropdown-toggle` / `data-collapse-toggle` / `data-tooltip-target` / `data-popover-target` dans `app/views/public/**`, donc seuls les imports sont à retirer, aucun contrôleur Stimulus à enregistrer côté public.

### Ce qui N'EST PAS modifié

- `package.json` : `flowbite` reste en dépendance (requis pour le datepicker et potentiellement pour `tailwind.config.js`).
- `tailwindcss-stimulus-components` : déjà importé, pas utilisé mais conservé (dépendance légère, pas source de la fuite).
- Contrôleurs Stimulus existants : `booking`, `space_booking`, `dashboard_calendar`, `turbo_modal`, `cycle_actions`, `human_roles`, `notes`.
- Toutes les vues n'ayant pas de data-attrs Flowbite à migrer.

## Architecture des 4 contrôleurs

### Principe commun

- API compatible 1:1 avec Flowbite côté HTML, au détail près que `data-X-toggle="id"` devient `data-X-toggle-value="id"` (convention Stimulus values).
- `connect()` attache les listeners sur l'élément porteur.
- `disconnect()` les retire explicitement et détruit les instances Popper.js — appelé automatiquement par Stimulus quand Turbo remplace le `<body>`.
- Popper.js est importé depuis `@popperjs/core` (vérifié présent dans `node_modules/@popperjs/core`, dep transitive via flowbite). Si une future suppression de flowbite casse cette résolution, il faudra l'ajouter explicitement via `yarn add @popperjs/core`.
- Pas de listeners globaux sur `document` ou `window` autres que ce qui est strictement nécessaire (`click@window` pour fermer dropdown/popover, attaché via `data-action` Stimulus qui est nettoyé automatiquement).

### `dropdown_controller.js`

```
Usage HTML :
  button(data-controller="dropdown"
         data-action="click->dropdown#toggle click@window->dropdown#hideOnClickOutside"
         data-dropdown-toggle-value="accueilDropdown")

Comportement :
- toggle() : bascule la classe 'hidden' sur document.getElementById(this.toggleValue).
- hideOnClickOutside(event) : si event.target n'est ni le trigger ni dans le menu, cache.
- disconnect() : rien à nettoyer manuellement (tout passe par data-action).
```

### `collapse_controller.js`

```
Usage HTML :
  button(data-controller="collapse"
         data-action="click->collapse#toggle"
         data-collapse-toggle-value="navbar-dropdown")

Comportement :
- toggle() : bascule 'hidden' sur document.getElementById(this.toggleValue).
- Met à jour aria-expanded sur le trigger.
```

### `tooltip_controller.js`

```
Usage HTML (trigger) :
  div(data-controller="tooltip"
      data-action="mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide"
      data-tooltip-target-value="tooltip-human-42")

La div cible (#tooltip-human-42) existe déjà dans les partials _tooltips avec les classes
'invisible opacity-0' pour l'état fermé.

Comportement :
- show() : lazy-instancie Popper (this.popper) sur target, remplace 'invisible opacity-0' par 'visible opacity-100'.
- hide() : remplace 'visible opacity-100' par 'invisible opacity-0'.
- disconnect() : this.popper?.destroy(); this.popper = null.
```

### `popover_controller.js`

```
Usage HTML (trigger) :
  div(data-controller="popover"
      data-action="click->popover#toggle click@window->popover#hideOnClickOutside"
      data-popover-target-value="popover-event-12"
      data-popover-trigger-value="click")

Ou pour l'icône help :
  button(data-controller="popover"
         data-action="mouseenter->popover#show mouseleave->popover#hide"
         data-popover-target-value="popover-tier-soutien"
         data-popover-trigger-value="hover")

Comportement :
- toggle() : bascule visibilité, instancie Popper à la première ouverture.
- show()/hide() : idem tooltip.
- hideOnClickOutside(event) : si ouvert et clic hors du target et hors du trigger, hide.
- disconnect() : destroy Popper.
```

## Plan de test manuel

1. `bin/dev` ; ouvrir `http://localhost:3000` sur la page calendar (page la plus chargée en popovers).
2. Ouvrir DevTools → Console, relever `getEventListeners(document.body).click?.length ?? 0` (baseline).
3. Naviguer 15 fois entre : calendar → bookings → organisation → reports → calendar → ...
4. Re-relever le count click. **Critère** : le count ne croît pas de façon proportionnelle au nombre de navigations (idéalement stable, au plus +1 ou +2 dus à d'autres lib).
5. Fonctionnels à valider :
   - Calendar : clic sur une réservation ouvre un popover, clic ailleurs le ferme.
   - Calendar : hover sur un badge `room/space` affiche son tooltip.
   - Navbar "Accueil" : clic ouvre le dropdown, clic ailleurs le ferme.
   - Navbar mobile (viewport < md) : hamburger ouvre/ferme le menu.
   - Grille rôles (organisation) : hover sur un nom d'humain affiche le tooltip.
   - Formulaire booking : datepicker fonctionne (non touché mais à vérifier).

## Hors périmètre (peut faire l'objet d'un suivi ultérieur)

- `Human.all.each` dans `humans/_tooltips` rendu pour toutes les pages via le layout — inefficace mais indépendant de la fuite listener.
- Mise à niveau de Flowbite ou suppression complète de la dépendance.
- Migration du datepicker vers une alternative Stimulus-friendly.
- Audit similaire côté entrypoint `public.js` si la migration y est étendue.
